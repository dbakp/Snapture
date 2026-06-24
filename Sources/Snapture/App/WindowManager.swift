import AppKit
import SwiftUI

@MainActor
final class WindowManager {
    private var editors: [EditorWindowController] = []

    func openEditor(with image: NSImage) {
        let controller = EditorWindowController(image: image) { [weak self] closed in
            guard let self else { return }
            self.editors.removeAll { $0 === closed }
            self.syncActivationPolicy()
        }
        editors.append(controller)
        // While an editor is open, become a regular app so it shows in the Dock
        // and the ⌘-Tab app switcher — an accessory app's window is otherwise
        // hard to navigate back to. Revert to accessory when the last one closes.
        syncActivationPolicy()
        controller.showWindow()
    }

    private func syncActivationPolicy() {
        let desired: NSApplication.ActivationPolicy = editors.isEmpty ? .accessory : .regular
        guard NSApp.activationPolicy() != desired else { return }
        NSApp.setActivationPolicy(desired)
        if desired == .regular { NSApp.activate(ignoringOtherApps: true) }
    }
}
