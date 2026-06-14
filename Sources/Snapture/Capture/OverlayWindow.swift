import AppKit

/// A borderless capture overlay that can still become the key window.
///
/// `NSWindow` returns `false` from `canBecomeKey`/`canBecomeMain` for the
/// `.borderless` style mask, which means the window never receives `keyDown` —
/// so Escape-to-cancel silently does nothing. Capture overlays need keyboard
/// input, so they opt back in here.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
