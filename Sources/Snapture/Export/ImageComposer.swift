import SwiftUI
import AppKit

@MainActor
enum ImageComposer {
    /// Render the editor composition at the cropped image's native pixel size + padding.
    static func compose(state: EditorState) -> NSImage {
        let image = state.croppedImage
        let imageSize = image.size
        let padding = state.padding
        let chromeH = state.chromeHeight
        let canvasSize = CGSize(width: imageSize.width + padding * 2,
                                height: imageSize.height + chromeH + padding * 2)

        let layout = CanvasLayout(
            canvasSize: canvasSize,
            imageRect: CGRect(x: padding, y: padding + chromeH, width: imageSize.width, height: imageSize.height),
            viewSize: canvasSize,
            canvasOrigin: .zero,
            displayScale: 1.0
        )

        let view = CompositionView(state: state, layout: layout)
            .frame(width: canvasSize.width, height: canvasSize.height)

        let renderer = ImageRenderer(content: view)
        // Render at 2x to keep crispness even when the input was at 1x.
        renderer.scale = max(2, NSScreen.main?.backingScaleFactor ?? 2)
        renderer.isOpaque = false

        if let cg = renderer.cgImage {
            return NSImage(cgImage: cg, size: canvasSize)
        }
        if let ns = renderer.nsImage { return ns }
        return image
    }
}
