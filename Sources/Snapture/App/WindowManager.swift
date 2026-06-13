import AppKit
import SwiftUI

@MainActor
final class WindowManager {
    private var editors: [EditorWindowController] = []

    func openEditor(with image: NSImage) {
        let controller = EditorWindowController(image: image) { [weak self] closed in
            self?.editors.removeAll { $0 === closed }
        }
        editors.append(controller)
        controller.showWindow()
    }
}
