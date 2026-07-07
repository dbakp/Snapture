import AppKit

/// A borderless, non-activating panel for capture overlays.
///
/// Two properties make capture UI behave correctly:
///
/// - `canBecomeKey`: borderless windows refuse key status by default, which
///   would break Escape-to-cancel (keyDown never arrives).
/// - NSPanel + `.nonactivatingPanel` (included in the style mask at init): the
///   overlay takes key status WITHOUT activating the app. Activating would
///   raise Snapture's own windows — an editor open in the background would jump
///   above the window the user is trying to capture, and the screenshot would
///   show Snapture's window on top instead of what the user actually sees.
final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Panels hide when the app deactivates by default. A capture overlay must
    // stay up (and cancellable) even if the user switches apps mid-capture —
    // otherwise the pending capture would be orphaned with no way to cancel.
    override var hidesOnDeactivate: Bool {
        get { false }
        set {}
    }
}
