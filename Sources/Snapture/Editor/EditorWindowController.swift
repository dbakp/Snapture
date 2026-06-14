import AppKit
import SwiftUI

@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    private let state: EditorState
    private let window: NSWindow
    private let onClose: (EditorWindowController) -> Void
    private let autoCopyOnOpen: Bool

    init(image: NSImage, onClose: @escaping (EditorWindowController) -> Void) {
        let prefs = (NSApp.delegate as? AppDelegate)?.preferences ?? Preferences()
        self.state = EditorState(image: image, preferences: prefs)
        self.onClose = onClose
        self.autoCopyOnOpen = prefs.autoCopyOnCapture

        let imageSize = image.size
        let initialWidth: CGFloat = max(980, min(imageSize.width + 480, 1500))
        let initialHeight: CGFloat = max(620, min(imageSize.height + 280, 1000))

        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
            styleMask: style,
            backing: .buffered,
            defer: false
        )

        super.init()
        configureWindow()
    }

    private func configureWindow() {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Snapture"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("SnaptureEditor")

        let root = EditorView()
            .environmentObject(state)
            .frame(minWidth: 940, minHeight: 520)

        window.contentView = NSHostingView(rootView: root)
    }

    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // "Auto-copy on capture": put the composed image on the clipboard the
        // moment the editor opens, so a paste works even with zero edits.
        if autoCopyOnOpen {
            Exporter.copyToClipboard(ImageComposer.compose(state: state))
        }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in self.onClose(self) }
    }
}
