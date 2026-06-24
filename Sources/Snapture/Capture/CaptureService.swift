import AppKit
import ScreenCaptureKit
import CoreGraphics

@MainActor
final class CaptureService {
    static let shared = CaptureService()
    private init() {}

    private var activeOverlays: [SelectionOverlayWindow] = []
    private var activeWindowPickers: [WindowPickOverlay] = []
    private var didRequestPermission = false

    /// Guards the interactive capture flows (area select, window pick) against
    /// re-entry. A second hotkey press while an overlay is up would otherwise
    /// clobber the live session's state and orphan its full-screen overlay.
    private var isCapturing = false

    // Per-pick-session preview state for the window picker.
    private var pickWindowsByID: [CGWindowID: SCWindow] = [:]
    private var previewCache: [CGWindowID: NSImage] = [:]
    private var previewInFlight: Set<CGWindowID> = []
    private var prefetchTask: Task<Void, Never>?
    /// Bumped whenever a pick session starts or ends. A preview capture that
    /// completes after its session is gone re-checks this and bails, so it can
    /// never write a stale thumbnail into a later session.
    private var pickGeneration = 0

    func captureArea() async -> NSImage? {
        guard ensureScreenRecordingPermission() else { return nil }
        guard let selection = await selectArea() else { return nil }
        return await captureRect(selection.rect, displayID: selection.displayID)
    }

    func captureFullScreen() async -> NSImage? {
        guard ensureScreenRecordingPermission() else { return nil }
        // The display the cursor is on — not always the primary.
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main else { return nil }
        let rect = CGRect(x: 0, y: 0, width: screen.frame.width, height: screen.frame.height)
        return await captureRect(rect, displayID: screen.displayID)
    }

    func captureWindow() async -> NSImage? {
        guard ensureScreenRecordingPermission() else { return nil }
        guard let windowID = await pickWindow() else { return nil }
        return await captureWindow(windowID: windowID)
    }

    // MARK: - Permission

    /// Returns true when Screen Recording is authorized.
    ///
    /// First miss: triggers the one-time system prompt (macOS shows it at most
    /// once per app identity) and aborts the capture so the user can respond.
    /// Later misses: shows our own alert with a shortcut to System Settings —
    /// the system won't re-prompt after a denial, and silently doing nothing
    /// is the worst possible behavior.
    private func ensureScreenRecordingPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }

        if !didRequestPermission {
            didRequestPermission = true
            CGRequestScreenCaptureAccess()
            return false
        }

        presentPermissionAlert()
        return false
    }

    private func presentPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Snapture needs Screen Recording permission"
        alert.informativeText = """
        Enable Snapture under System Settings → Privacy & Security → Screen Recording, \
        then quit and relaunch Snapture (macOS applies this permission at launch).
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Window picking

    private func pickWindow() async -> CGWindowID? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            return nil
        }
        let myPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        // SCShareableContent lists windows front-to-back; keep that order so the
        // pick overlay's "first hit wins" matches what's visually on top.
        var byID: [CGWindowID: SCWindow] = [:]
        let candidates: [PickableWindow] = content.windows.compactMap { w in
            guard w.isOnScreen,
                  w.windowLayer == 0,
                  w.frame.width > 40, w.frame.height > 40,
                  w.owningApplication?.processID != myPID else { return nil }
            byID[w.windowID] = w
            return PickableWindow(
                id: w.windowID,
                frame: w.frame,
                title: w.title ?? "",
                appName: w.owningApplication?.applicationName ?? ""
            )
        }
        guard !candidates.isEmpty else { return nil }

        // Fresh preview state for this pick session.
        pickGeneration &+= 1
        pickWindowsByID = byID
        previewCache = [:]
        previewInFlight = []

        let pickedID: CGWindowID? = await withCheckedContinuation { (continuation: CheckedContinuation<CGWindowID?, Never>) in
            var didResume = false
            let resume: (CGWindowID?) -> Void = { [weak self] id in
                guard !didResume else { return }
                didResume = true
                self?.dismissWindowPickers()
                continuation.resume(returning: id)
            }

            var overlays: [WindowPickOverlay] = []
            for screen in NSScreen.screens {
                let overlay = WindowPickOverlay(
                    screen: screen,
                    candidates: candidates,
                    onPick: { resume($0) },
                    onCancel: { resume(nil) },
                    onHoverPreview: { [weak self] id in
                        // Hovering jumps a window to the front of the preview queue.
                        Task { @MainActor in await self?.loadPreview(id) }
                    }
                )
                overlays.append(overlay)
                overlay.present()
            }
            self.activeWindowPickers = overlays
            if overlays.isEmpty { resume(nil) }

            // Prefetch every candidate front-to-back so thumbnails are usually
            // ready before the cursor reaches them.
            self.prefetchTask = Task { @MainActor [weak self] in
                for candidate in candidates {
                    if Task.isCancelled { return }
                    await self?.loadPreview(candidate.id)
                }
            }
        }

        return pickedID
    }

    /// Capture (if not already cached/in-flight) a downscaled thumbnail of the
    /// window's *real* content — the same `desktopIndependentWindow` filter the
    /// final capture uses — and hand it to every on-screen picker overlay.
    private func loadPreview(_ id: CGWindowID) async {
        guard previewCache[id] == nil,
              !previewInFlight.contains(id),
              let window = pickWindowsByID[id] else { return }
        let generation = pickGeneration
        previewInFlight.insert(id)
        let image = await capturePreview(of: window)
        // The session may have ended (or a new one started) while we were
        // awaiting the capture — if so, drop this result on the floor.
        guard generation == pickGeneration else { return }
        previewInFlight.remove(id)
        guard let image else { return }
        previewCache[id] = image
        for overlay in activeWindowPickers { overlay.setPreview(image, for: id) }
    }

    private func capturePreview(of window: SCWindow) async -> NSImage? {
        let frame = window.frame
        guard frame.width >= 1, frame.height >= 1 else { return nil }

        // Cap the long edge — a preview never needs full Retina resolution, and
        // this keeps a screen full of windows fast to capture.
        let maxEdge: CGFloat = 1200
        let scale = min(1.0, maxEdge / max(frame.width, frame.height))

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = max(1, Int((frame.width * scale).rounded()))
        config.height = max(1, Int((frame.height * scale).rounded()))
        config.scalesToFit = true
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA

        do {
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: cgImage, size: NSSize(width: frame.width, height: frame.height))
        } catch {
            return nil
        }
    }

    private func dismissWindowPickers() {
        pickGeneration &+= 1   // invalidate any preview captures still in flight
        prefetchTask?.cancel()
        prefetchTask = nil
        for picker in activeWindowPickers { picker.dismiss() }
        activeWindowPickers = []
        pickWindowsByID = [:]
        previewCache = [:]
        previewInFlight = []
    }

    private func captureWindow(windowID: CGWindowID) async -> NSImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let window = content.windows.first(where: { $0.windowID == windowID }) else { return nil }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = Self.backingScale(forQuartzFrame: window.frame)
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.scalesToFit = false
        config.showsCursor = Self.includeCursorPreference
        config.pixelFormat = kCVPixelFormatType_32BGRA

        do {
            // Let the pick overlay fully disappear before the snapshot.
            try await Task.sleep(nanoseconds: 80_000_000)
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: cgImage,
                           size: NSSize(width: window.frame.width, height: window.frame.height))
        } catch {
            NSLog("Snapture window capture failed: \(error)")
            return nil
        }
    }

    /// Backing scale of the screen containing the window's centre.
    /// `cgFrame` is in Quartz global coordinates (top-left origin).
    private static func backingScale(forQuartzFrame cgFrame: CGRect) -> CGFloat {
        let primaryH = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height ?? 0
        let centerAppKit = CGPoint(x: cgFrame.midX, y: primaryH - cgFrame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(centerAppKit) }
        return screen?.backingScaleFactor ?? 2
    }

    // MARK: - Area selection

    private struct Selection: Sendable {
        let rect: CGRect    // in display pixel coordinates, origin top-left
        let displayID: CGDirectDisplayID
    }

    private func selectArea() async -> Selection? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Selection?, Never>) in
            var didResume = false
            let resume: (Selection?) -> Void = { [weak self] selection in
                guard !didResume else { return }
                didResume = true
                self?.dismissOverlays()
                continuation.resume(returning: selection)
            }

            // One overlay per physical screen — keyed by the screen's own display
            // ID. The capture step resolves the SCDisplay from that ID, so we no
            // longer skip a screen just because SCShareableContent didn't list a
            // matching display (which silently dropped secondary monitors).
            var overlays: [SelectionOverlayWindow] = []
            for screen in NSScreen.screens {
                let overlay = SelectionOverlayWindow(screen: screen, displayID: screen.displayID) { rect, displayID in
                    resume(Selection(rect: rect, displayID: displayID))
                } onCancel: {
                    resume(nil)
                }
                overlays.append(overlay)
                overlay.present()
            }
            self.activeOverlays = overlays
            if overlays.isEmpty { resume(nil) }
        }
    }

    private func dismissOverlays() {
        for overlay in activeOverlays { overlay.dismiss() }
        activeOverlays = []
    }

    // MARK: - Screenshot

    private func captureRect(_ rect: CGRect, displayID: CGDirectDisplayID) async -> NSImage? {
        guard let displays = try? await SCShareableContent
                .excludingDesktopWindows(false, onScreenWindowsOnly: true).displays,
              let display = Self.resolveDisplay(id: displayID, in: displays) else {
            NSLog("Snapture: could not resolve SCDisplay for id \(displayID)")
            return nil
        }

        let config = SCStreamConfiguration()
        let scale = Self.backingScale(for: display)
        config.width = Int(rect.width * scale)
        config.height = Int(rect.height * scale)
        config.sourceRect = rect
        config.scalesToFit = false
        config.showsCursor = Self.includeCursorPreference
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let filter = SCContentFilter(display: display, excludingWindows: [])

        do {
            // Brief delay so any overlay window is fully off-screen before the snapshot.
            try await Task.sleep(nanoseconds: 80_000_000)
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let size = NSSize(width: rect.width, height: rect.height)
            return NSImage(cgImage: cgImage, size: size)
        } catch {
            NSLog("Snapture capture failed: \(error)")
            return nil
        }
    }

    private static func backingScale(for display: SCDisplay) -> CGFloat {
        let screen = NSScreen.screens.first { $0.displayID == display.displayID }
        return screen?.backingScaleFactor ?? 2.0
    }

    /// Find the SCDisplay for a display ID. Falls back to matching by global
    /// bounds when the ID from NSScreen doesn't line up with SCDisplay.displayID.
    private static func resolveDisplay(id: CGDirectDisplayID, in displays: [SCDisplay]) -> SCDisplay? {
        if let d = displays.first(where: { $0.displayID == id }) { return d }
        let bounds = CGDisplayBounds(id)
        guard !bounds.isEmpty else { return nil }
        return displays.first { $0.frame == bounds }
            ?? displays.first { abs($0.frame.width - bounds.width) < 2 && abs($0.frame.height - bounds.height) < 2 }
    }

    /// Whether the user wants the mouse cursor baked into captures. Read from the
    /// shared preferences via the app delegate, matching how the editor reads them.
    private static var includeCursorPreference: Bool {
        (NSApp.delegate as? AppDelegate)?.preferences.includeCursor ?? false
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }
}
