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

    func captureArea() async -> NSImage? {
        guard ensureScreenRecordingPermission() else { return nil }
        guard let selection = await selectArea() else { return nil }
        return await captureRect(selection.rect, displayID: selection.displayID)
    }

    func captureFullScreen() async -> NSImage? {
        guard ensureScreenRecordingPermission() else { return nil }
        guard let display = await primaryDisplay() else { return nil }
        let rect = CGRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height))
        return await captureRect(rect, displayID: display.displayID)
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
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            return nil
        }
        let myPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        // SCShareableContent lists windows front-to-back; keep that order so the
        // pick overlay's "first hit wins" matches what's visually on top.
        let candidates: [PickableWindow] = content.windows.compactMap { w in
            guard w.isOnScreen,
                  w.windowLayer == 0,
                  w.frame.width > 40, w.frame.height > 40,
                  w.owningApplication?.processID != myPID else { return nil }
            return PickableWindow(id: w.windowID, frame: w.frame, title: w.title ?? "")
        }
        guard !candidates.isEmpty else { return nil }

        return await withCheckedContinuation { (continuation: CheckedContinuation<CGWindowID?, Never>) in
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
                    onCancel: { resume(nil) }
                )
                overlays.append(overlay)
                overlay.present()
            }
            self.activeWindowPickers = overlays
            if overlays.isEmpty { resume(nil) }
        }
    }

    private func dismissWindowPickers() {
        for picker in activeWindowPickers { picker.dismiss() }
        activeWindowPickers = []
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
        config.showsCursor = false
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
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            return nil
        }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Selection?, Never>) in
            var didResume = false
            let resume: (Selection?) -> Void = { [weak self] selection in
                guard !didResume else { return }
                didResume = true
                self?.dismissOverlays()
                continuation.resume(returning: selection)
            }

            var overlays: [SelectionOverlayWindow] = []
            for screen in NSScreen.screens {
                guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { continue }
                let overlay = SelectionOverlayWindow(screen: screen, display: display) { rect, display in
                    resume(Selection(rect: rect, displayID: display.displayID))
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

    private func primaryDisplay() async -> SCDisplay? {
        let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content?.displays.first
    }

    private func captureRect(_ rect: CGRect, displayID: CGDirectDisplayID) async -> NSImage? {
        guard let display = try? await SCShareableContent
                .excludingDesktopWindows(false, onScreenWindowsOnly: true)
                .displays.first(where: { $0.displayID == displayID }) else { return nil }

        let config = SCStreamConfiguration()
        let scale = Self.backingScale(for: display)
        config.width = Int(rect.width * scale)
        config.height = Int(rect.height * scale)
        config.sourceRect = rect
        config.scalesToFit = false
        config.showsCursor = false
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
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }
}
