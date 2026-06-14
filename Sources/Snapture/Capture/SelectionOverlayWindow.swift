import AppKit
import ScreenCaptureKit

@MainActor
final class SelectionOverlayWindow {
    private let window: NSWindow
    private let view: SelectionOverlayView
    private let screen: NSScreen
    private let display: SCDisplay
    private let onSelect: (CGRect, SCDisplay) -> Void
    private let onCancel: () -> Void

    init(
        screen: NSScreen,
        display: SCDisplay,
        onSelect: @escaping (CGRect, SCDisplay) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.screen = screen
        self.display = display
        self.onSelect = onSelect
        self.onCancel = onCancel

        self.window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        self.view = SelectionOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        window.contentView = view
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.acceptsMouseMovedEvents = true

        view.onCommit = { [weak self] localRect in
            guard let self else { return }
            let displayRect = self.toDisplayPointsRect(localRect: localRect)
            self.onSelect(displayRect, self.display)
        }
        view.onCancel = { [weak self] in self?.onCancel() }
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.makeFirstResponder(view)
        NSCursor.crosshair.push()
    }

    func dismiss() {
        NSCursor.pop()
        window.orderOut(nil)
    }

    /// Convert view-local points (AppKit, origin bottom-left)
    /// → display-local points (Quartz, origin top-left).
    /// SCStreamConfiguration.sourceRect is in POINTS, not pixels.
    private func toDisplayPointsRect(localRect: NSRect) -> CGRect {
        let flippedY = screen.frame.height - localRect.origin.y - localRect.height
        return CGRect(
            x: localRect.origin.x,
            y: flippedY,
            width: localRect.width,
            height: localRect.height
        )
    }
}

final class SelectionOverlayView: NSView {
    var onCommit: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private var cursorPosition: NSPoint = .zero

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    // Deliver crosshair mouseMoved events on every screen's overlay, not just
    // the key window's (only one overlay can be key on multi-display setups).
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
        // Dim background everywhere except the selection.
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        if currentRect.width > 1 && currentRect.height > 1 {
            // Clear the selection
            NSColor.clear.setFill()
            currentRect.fill(using: .clear)

            // Selection border
            let path = NSBezierPath(rect: currentRect.insetBy(dx: 0.5, dy: 0.5))
            NSColor.white.setStroke()
            path.lineWidth = 1.5
            path.stroke()

            // Dimension badge
            drawDimensionBadge(for: currentRect)
        } else {
            drawCrosshair(at: cursorPosition)
        }
    }

    private func drawCrosshair(at point: NSPoint) {
        let color = NSColor.white.withAlphaComponent(0.6)
        color.setStroke()
        let h = NSBezierPath()
        h.move(to: NSPoint(x: 0, y: point.y))
        h.line(to: NSPoint(x: bounds.width, y: point.y))
        h.move(to: NSPoint(x: point.x, y: 0))
        h.line(to: NSPoint(x: point.x, y: bounds.height))
        h.lineWidth = 0.5
        h.stroke()
    }

    private func drawDimensionBadge(for rect: NSRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let size = attr.size()
        let badgeRect = NSRect(
            x: rect.maxX - size.width - 14,
            y: rect.minY - size.height - 12,
            width: size.width + 10,
            height: size.height + 6
        ).integral
        if badgeRect.minY < 0 {
            let aboveRect = NSRect(
                x: rect.maxX - size.width - 14,
                y: rect.maxY + 6,
                width: size.width + 10,
                height: size.height + 6
            ).integral
            drawBadge(in: aboveRect, with: attr, size: size)
        } else {
            drawBadge(in: badgeRect, with: attr, size: size)
        }
    }

    private func drawBadge(in rect: NSRect, with attr: NSAttributedString, size: NSSize) {
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        attr.draw(at: NSPoint(x: rect.minX + 5, y: rect.minY + 3))
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(
            x: min(start.x, p.x),
            y: min(start.y, p.y),
            width: abs(p.x - start.x),
            height: abs(p.y - start.y)
        )
        cursorPosition = p
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { startPoint = nil }
        guard currentRect.width >= 4, currentRect.height >= 4 else {
            onCancel?()
            return
        }
        onCommit?(currentRect)
    }

    override func mouseMoved(with event: NSEvent) {
        cursorPosition = convert(event.locationInWindow, from: nil)
        if startPoint == nil { needsDisplay = true }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 0x35 { // Escape
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}
