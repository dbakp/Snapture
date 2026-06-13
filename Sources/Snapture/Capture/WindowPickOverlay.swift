import AppKit
import ScreenCaptureKit

/// Lightweight, Sendable description of a window the user can pick.
/// `frame` is in Quartz global coordinates (origin top-left of primary display).
struct PickableWindow: Sendable {
    let id: CGWindowID
    let frame: CGRect
    let title: String
}

/// Full-screen overlay that highlights the window under the cursor;
/// click picks it, Escape cancels.
@MainActor
final class WindowPickOverlay {
    private let window: NSWindow
    private let view: WindowPickView

    init(
        screen: NSScreen,
        candidates: [PickableWindow],
        onPick: @escaping (CGWindowID) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? screen.frame.height

        window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
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
    }

    func present() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSCursor.pointingHand.push()
    }

    func dismiss() {
        NSCursor.pop()
        window.orderOut(nil)
    }
}

final class WindowPickView: NSView {
    var onPick: ((CGWindowID) -> Void)?
    var onCancel: (() -> Void)?

    private let candidates: [PickableWindow]   // front-to-back order from SCShareableContent
    private let screenOrigin: NSPoint           // this screen's AppKit global origin
    private let primaryScreenHeight: CGFloat
    private var hovered: PickableWindow?

    init(frame: NSRect, candidates: [PickableWindow], screenOrigin: NSPoint, primaryScreenHeight: CGFloat) {
        self.candidates = candidates
        self.screenOrigin = screenOrigin
        self.primaryScreenHeight = primaryScreenHeight
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override var acceptsFirstResponder: Bool { true }

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

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.30).setFill()
        bounds.fill()

        guard let hovered else { return }
        let local = localRect(forGlobalQuartz: hovered.frame)

        // Punch out the hovered window and ring it.
        NSColor.clear.setFill()
        local.fill(using: .clear)

        let ring = NSBezierPath(roundedRect: local.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.setStroke()
        ring.lineWidth = 3
        ring.stroke()

        // Window title label above the highlight.
        if !hovered.title.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let label = NSAttributedString(string: hovered.title, attributes: attrs)
            let size = label.size()
            let badge = NSRect(
                x: local.midX - size.width / 2 - 8,
                y: min(local.maxY + 8, bounds.height - size.height - 12),
                width: size.width + 16,
                height: size.height + 8
            )
            NSColor.black.withAlphaComponent(0.75).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 5, yRadius: 5).fill()
            label.draw(at: NSPoint(x: badge.minX + 8, y: badge.minY + 4))
        }
    }

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

    override func mouseMoved(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let cg = quartzPoint(fromLocal: local)
        // candidates are front-to-back: first hit wins.
        let hit = candidates.first { $0.frame.contains(cg) }
        if hit?.id != hovered?.id {
            hovered = hit
            needsDisplay = true
        }
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
