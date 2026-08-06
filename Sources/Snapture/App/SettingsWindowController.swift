import AppKit
import SwiftUI

/// Owns the Settings window directly. The SwiftUI `Settings` scene can only be
/// opened via the private `showSettingsWindow:` selector from AppKit contexts,
/// which Apple has been quietly breaking release over release — a real window
/// we control is deterministic.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(preferences: Preferences) {
        if window == nil {
            let host = NSHostingView(rootView: SettingsView().environmentObject(preferences))
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "Snapture Settings"
            w.contentView = host
            w.setContentSize(host.fittingSize)   // fit the tabs + version footer
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
