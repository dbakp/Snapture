import AppKit
import ScreenCaptureKit

/// Lightweight, Sendable description of a window the user can pick.
/// `frame` is in Quartz global coordinates (origin top-left of primary display).
struct PickableWindow: Sendable {
    let id: CGWindowID
    let frame: CGRect
    let title: String
    let appName: String

    /// Human-facing label: "App — Window Title", or whichever half exists.
    var label: String {
        switch (appName.isEmpty, title.isEmpty) {
        case (false, false): return "\(appName) — \(title)"
        case (false, true):  return appName
        case (true, false):  return title
        case (true, true):   return "Window"
        }
    }
}

/// Full-screen overlay that highlights the window under the cursor and shows a
/// live thumbnail of its *actual* content — so what you see is exactly what you
/// capture, even when the target window is hidden behind others. Click picks it,
/// Escape cancels.
@MainActor
final class WindowPickOverlay {
    private let window: NSWindow
    private let view: WindowPickView

    init(
        screen: NSScreen,
        candidates: [PickableWindow],
        onPick: @escaping (CGWindowID) -> Void,
        onCancel: @escaping () -> Void,
        onHoverPreview: @escaping (CGWindowID) -> Void
    ) {
        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? screen.frame.height

        window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // Global-coordinate placement; passing `screen:` would double-offset
        // overlays on secondary displays. See SelectionOverlayWindow.
        window.setFrame(screen.frame, display: false)
        view = WindowPickView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            candidates: candidates,
            screenOrigin: screen.frame.origin,
            primaryScreenHeight: primaryHeight
        )
        window.contentView = view
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.acceptsMouseMovedEvents = true

        view.onPick = onPick
        view.onCancel = onCancel
        view.onHoverPreview = onHoverPreview
    }

    func present() {
        // Activate so the overlay can actually hold key status — a background
        // accessory app's window won't otherwise receive keyDown (Escape).
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.makeFirstResponder(view)
        NSCursor.pointingHand.push()
    }

    func dismiss() {
        NSCursor.pop()
        window.orderOut(nil)
    }

    /// Feed a captured preview thumbnail for a window into the overlay.
    func setPreview(_ image: NSImage, for id: CGWindowID) {
        view.setPreview(image, for: id)
    }
}

final class WindowPickView: NSView {
    var onPick: ((CGWindowID) -> Void)?
    var onCancel: (() -> Void)?
    var onHoverPreview: ((CGWindowID) -> Void)?

    private let candidates: [PickableWindow]   // front-to-back order from SCShareableContent
    private let screenOrigin: NSPoint           // this screen's AppKit global origin
    private let primaryScreenHeight: CGFloat
    private var hovered: PickableWindow?
    private var previews: [CGWindowID: NSImage] = [:]

    private let dimOpacity: CGFloat = 0.55
    private let cornerRadius: CGFloat = 6

    init(frame: NSRect, candidates: [PickableWindow], screenOrigin: NSPoint, primaryScreenHeight: CGFloat) {
        self.candidates = candidates
        self.screenOrigin = screenOrigin
        self.primaryScreenHeight = primaryScreenHeight
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override var acceptsFirstResponder: Bool { true }

    /// Stash a captured thumbnail; repaint if it belongs to the window currently
    /// under the cursor so the placeholder swaps to real content instantly.
    func setPreview(_ image: NSImage, for id: CGWindowID) {
        previews[id] = image
        if hovered?.id == id { needsDisplay = true }
    }

    // mouseMoved is normally only delivered to the key window. With one overlay
    // per screen, only one can be key — a tracking area with .activeAlways gets
    // hover events to every overlay regardless.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        ))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(dimOpacity).setFill()
        bounds.fill()

        // On multi-monitor setups, only the display under the cursor shows the
        // instructional hints — otherwise every other screen nags redundantly.
        let cursorHere = screenContainsCursor

        if let hovered {
            drawHovered(hovered)
        } else if cursorHere {
            drawCenteredHint("Move your cursor over a window to preview it")
        }
        if cursorHere {
            drawFooterHint("Click a window to capture it   ·   Esc to cancel")
        }
    }

    /// True when the OS cursor currently sits on this overlay's screen.
    private var screenContainsCursor: Bool {
        NSRect(origin: screenOrigin, size: bounds.size).contains(NSEvent.mouseLocation)
    }

    private func drawHovered(_ win: PickableWindow) {
        let local = localRect(forGlobalQuartz: win.frame)
        let clip = NSBezierPath(roundedRect: local, xRadius: cornerRadius, yRadius: cornerRadius)

        // A solid card behind the preview — casts the shadow and stands in until
        // the real thumbnail arrives, so we never reveal the wrong window.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
        shadow.shadowBlurRadius = 28
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.set()
        NSColor(white: 0.12, alpha: 1).setFill()
        clip.fill()
        NSGraphicsContext.restoreGraphicsState()

        if let image = previews[win.id] {
            NSGraphicsContext.saveGraphicsState()
            clip.addClip()
            image.draw(in: local, from: .zero, operation: .sourceOver, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            drawCentered("Loading preview…", in: local, fontSize: 13, color: NSColor(white: 0.7, alpha: 1))
        }

        // Accent ring.
        let ring = NSBezierPath(roundedRect: local.insetBy(dx: 1.5, dy: 1.5), xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.controlAccentColor.setStroke()
        ring.lineWidth = 3
        ring.stroke()

        drawTitleBadge(win.label, above: local)
    }

    private func drawTitleBadge(_ text: String, above local: NSRect) {
        guard !text.isEmpty else { return }
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail   // long "App — Title" labels get a trailing ellipsis
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: para
        ]
        let label = NSAttributedString(string: text, attributes: attrs)
        var size = label.size()
        // Clamp to the screen (not the window) so the badge never runs off-screen,
        // even for windows wider than the display they sit on.
        size.width = min(size.width, max(80, bounds.width - 48))
        let badge = NSRect(
            x: max(8, min(local.midX - size.width / 2 - 8, bounds.width - size.width - 24)),
            y: min(local.maxY + 8, bounds.height - size.height - 12),
            width: size.width + 16,
            height: size.height + 8
        )
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 6, yRadius: 6).fill()
        let textRect = NSRect(x: badge.minX + 8, y: badge.minY + 4, width: size.width, height: size.height)
        // .usesLineFragmentOrigin is required for .truncatesLastVisibleLine to apply.
        label.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private func drawCenteredHint(_ text: String) {
        let pill = pillRect(for: text, fontSize: 15, centeredAt: NSPoint(x: bounds.midX, y: bounds.midY))
        drawPill(text, in: pill, fontSize: 15)
    }

    private func drawFooterHint(_ text: String) {
        let pill = pillRect(for: text, fontSize: 13, centeredAt: NSPoint(x: bounds.midX, y: 64))
        drawPill(text, in: pill, fontSize: 13)
    }

    private func pillRect(for text: String, fontSize: CGFloat, centeredAt p: NSPoint) -> NSRect {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)]
        let s = (text as NSString).size(withAttributes: attrs)
        return NSRect(x: p.x - s.width / 2 - 16, y: p.y - s.height / 2 - 8,
                      width: s.width + 32, height: s.height + 16)
    }

    private func drawPill(_ text: String, in rect: NSRect, fontSize: CGFloat) {
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        drawCentered(text, in: rect, fontSize: fontSize, color: .white)
    }

    private func drawCentered(_ text: String, in rect: NSRect, fontSize: CGFloat, color: NSColor) {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: para
        ]
        let s = (text as NSString).size(withAttributes: attrs)
        let textRect = NSRect(x: rect.minX, y: rect.midY - s.height / 2, width: rect.width, height: s.height)
        (text as NSString).draw(in: textRect, withAttributes: attrs)
    }

    // MARK: - Coordinates

    /// Quartz global (top-left origin) → this view's local AppKit coords (bottom-left origin).
    private func localRect(forGlobalQuartz cg: CGRect) -> NSRect {
        let globalAppKitY = primaryScreenHeight - cg.maxY
        return NSRect(
            x: cg.minX - screenOrigin.x,
            y: globalAppKitY - screenOrigin.y,
            width: cg.width,
            height: cg.height
        )
    }

    /// This view's local AppKit point → Quartz global point.
    private func quartzPoint(fromLocal p: NSPoint) -> CGPoint {
        let globalAppKit = NSPoint(x: p.x + screenOrigin.x, y: p.y + screenOrigin.y)
        return CGPoint(x: globalAppKit.x, y: primaryScreenHeight - globalAppKit.y)
    }

    // MARK: - Events

    override func mouseMoved(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let cg = quartzPoint(fromLocal: local)
        // candidates are front-to-back: first hit wins.
        let hit = candidates.first { $0.frame.contains(cg) }
        if hit?.id != hovered?.id {
            hovered = hit
            needsDisplay = true
            if let hit { onHoverPreview?(hit.id) }   // prioritize fetching this window's thumbnail
        }
    }

    override func mouseEntered(with event: NSEvent) {
        needsDisplay = true   // cursor arrived on this screen — show its hints
    }

    override func mouseExited(with event: NSEvent) {
        // Cursor left this screen: drop the highlight and let the hints clear.
        hovered = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        // Recompute at click time in case the mouse never "moved".
        let local = convert(event.locationInWindow, from: nil)
        let cg = quartzPoint(fromLocal: local)
        if let hit = candidates.first(where: { $0.frame.contains(cg) }) {
            onPick?(hit.id)
        } else {
            onCancel?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 0x35 { // Escape
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}
