import AppKit
import SwiftUI

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let onCaptureArea: () -> Void
    private let onCaptureWindow: () -> Void
    private let onCaptureFullScreen: () -> Void
    private let onCaptureAreaDelayed: () -> Void
    private let onPreferences: () -> Void
    private let onShowWelcome: () -> Void
    private let onQuit: () -> Void

    init(
        onCaptureArea: @escaping () -> Void,
        onCaptureWindow: @escaping () -> Void,
        onCaptureFullScreen: @escaping () -> Void,
        onCaptureAreaDelayed: @escaping () -> Void,
        onPreferences: @escaping () -> Void,
        onShowWelcome: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onCaptureArea = onCaptureArea
        self.onCaptureWindow = onCaptureWindow
        self.onCaptureFullScreen = onCaptureFullScreen
        self.onCaptureAreaDelayed = onCaptureAreaDelayed
        self.onPreferences = onPreferences
        self.onShowWelcome = onShowWelcome
        self.onQuit = onQuit

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configure()
    }

    private func configure() {
        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "camera.viewfinder",
                accessibilityDescription: "Snapture"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Snapture — ⌘⇧2 area, ⌘⇧1 window, ⌃⌘3 full screen"
        }

        let menu = NSMenu()
        menu.addItem(makeItem(title: "Capture Area", shortcut: "2", modifiers: [.command, .shift], action: #selector(captureArea)))
        menu.addItem(makeItem(title: "Capture Window", shortcut: "1", modifiers: [.command, .shift], action: #selector(captureWindow)))
        menu.addItem(makeItem(title: "Capture Full Screen", shortcut: "3", modifiers: [.command, .control], action: #selector(captureFullScreen)))
        menu.addItem(makeItem(title: "Capture Area in 3 Seconds", shortcut: "", modifiers: [], action: #selector(captureAreaDelayed)))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Preferences…", shortcut: ",", modifiers: [.command], action: #selector(openPreferences)))
        menu.addItem(makeItem(title: "Welcome Guide", shortcut: "", modifiers: [], action: #selector(showWelcome)))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Quit Snapture", shortcut: "q", modifiers: [.command], action: #selector(quit)))
        statusItem.menu = menu
    }

    private func makeItem(title: String, shortcut: String, modifiers: NSEvent.ModifierFlags, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    @objc private func captureArea() { onCaptureArea() }
    @objc private func captureWindow() { onCaptureWindow() }
    @objc private func captureFullScreen() { onCaptureFullScreen() }
    @objc private func captureAreaDelayed() { onCaptureAreaDelayed() }
    @objc private func openPreferences() { onPreferences() }
    @objc private func showWelcome() { onShowWelcome() }
    @objc private func quit() { onQuit() }
}
