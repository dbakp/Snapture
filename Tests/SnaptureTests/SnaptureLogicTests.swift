import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import Snapture

@MainActor
final class SnaptureLogicTests: XCTestCase {

    private func solidImage(width: CGFloat, height: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image
    }

    private func makeState(imageWidth: CGFloat = 200, imageHeight: CGFloat = 200) -> EditorState {
        EditorState(image: solidImage(width: imageWidth, height: imageHeight), preferences: Preferences())
    }

    // MARK: - Arrow geometry (the CGRect.width abs-value trap)

    func testArrowTailTipWithNegativeSize() {
        var ann = Annotation.make(kind: .arrow, frame: .zero, defaults: AnnotationDefaults())
        ann.frame = CGRect(x: 250, y: 200, width: -100, height: -100)
        XCTAssertEqual(ann.arrowTail, CGPoint(x: 250, y: 200))
        XCTAssertEqual(ann.arrowTip, CGPoint(x: 150, y: 100), "tip must use signed size.width, not abs frame.width")
    }

    func testMovedByPreservesNegativeSize() {
        let rect = CGRect(x: 250, y: 200, width: -100, height: -50)
        let moved = rect.movedBy(dx: 10, dy: 20)
        XCTAssertEqual(moved.origin, CGPoint(x: 260, y: 220))
        XCTAssertEqual(moved.size.width, -100, "movedBy must not standardize the rect")
        XCTAssertEqual(moved.size.height, -50)
    }

    // MARK: - Undo / redo

    func testUndoRedoRoundtrip() {
        let state = makeState()
        state.padding = 10
        state.snapshot()
        state.padding = 20
        XCTAssertTrue(state.canUndo)
        state.undo()
        XCTAssertEqual(state.padding, 10)
        XCTAssertTrue(state.canRedo)
        state.redo()
        XCTAssertEqual(state.padding, 20)
    }

    func testSnapshotDeduplication() {
        let state = makeState()
        state.padding = 10
        state.snapshot()
        state.snapshot()   // identical — must be dropped
        state.padding = 99
        state.undo()
        XCTAssertEqual(state.padding, 10)
        XCTAssertFalse(state.canUndo, "duplicate snapshot should not create a second undo step")
    }

    func testPopLastSnapshotBacksOutCanceledAction() {
        let state = makeState()
        state.padding = 10
        state.snapshot()
        state.popLastSnapshot()
        XCTAssertFalse(state.canUndo)
    }

    func testUndoRestoresFrameStyleAndBackground() {
        let state = makeState()
        let originalBackground = state.background
        state.snapshot()
        state.frameStyle = .browser
        state.background = .solid(CodableColor(red: 0, green: 0, blue: 0))
        state.undo()
        XCTAssertEqual(state.frameStyle, .none)
        XCTAssertEqual(state.background, originalBackground)
    }

    // MARK: - Crop

    func testApplyCropResizesImageAndShiftsAnnotations() {
        let state = makeState(imageWidth: 200, imageHeight: 200)
        var box = Annotation.make(kind: .rectangle, frame: .zero, defaults: state.defaults)
        box.frame = CGRect(x: 60, y: 60, width: 10, height: 10)
        state.annotations = [box]

        state.applyCrop(rect: CGRect(x: 50, y: 50, width: 100, height: 100))

        XCTAssertEqual(state.croppedImage.size.width, 100, accuracy: 0.5)
        XCTAssertEqual(state.croppedImage.size.height, 100, accuracy: 0.5)
        XCTAssertEqual(state.annotations[0].frame.origin.x, 10, accuracy: 0.5)
        XCTAssertEqual(state.annotations[0].frame.origin.y, 10, accuracy: 0.5)
        XCTAssertNil(state.pendingCrop)
    }

    func testCropPreservesArrowDirection() {
        let state = makeState(imageWidth: 200, imageHeight: 200)
        var arrow = Annotation.make(kind: .arrow, frame: .zero, defaults: state.defaults)
        arrow.frame = CGRect(x: 150, y: 150, width: -50, height: -50)   // points up-left
        state.annotations = [arrow]

        state.applyCrop(rect: CGRect(x: 50, y: 50, width: 100, height: 100))

        let cropped = state.annotations[0]
        XCTAssertEqual(cropped.frame.size.width, -50, "crop shift must not flip arrow direction")
        XCTAssertEqual(cropped.arrowTail, CGPoint(x: 100, y: 100))
        XCTAssertEqual(cropped.arrowTip, CGPoint(x: 50, y: 50))
    }

    func testResetCropRestoresOriginal() {
        let state = makeState(imageWidth: 200, imageHeight: 200)
        state.applyCrop(rect: CGRect(x: 0, y: 0, width: 80, height: 80))
        XCTAssertEqual(state.croppedImage.size.width, 80, accuracy: 0.5)
        state.resetCrop()
        XCTAssertEqual(state.croppedImage.size.width, 200, accuracy: 0.5)
    }

    // MARK: - Z-order

    func testZOrderOperations() {
        let state = makeState()
        let a = Annotation.make(kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 10, height: 10), defaults: state.defaults)
        let b = Annotation.make(kind: .ellipse, frame: CGRect(x: 0, y: 0, width: 10, height: 10), defaults: state.defaults)
        let c = Annotation.make(kind: .triangle, frame: CGRect(x: 0, y: 0, width: 10, height: 10), defaults: state.defaults)
        state.annotations = [a, b, c]

        state.selectedAnnotationID = a.id
        state.bringToFront()
        XCTAssertEqual(state.annotations.map(\.id), [b.id, c.id, a.id])

        state.bringForward()   // already frontmost — no change
        XCTAssertEqual(state.annotations.map(\.id), [b.id, c.id, a.id])

        state.sendBackward()
        XCTAssertEqual(state.annotations.map(\.id), [b.id, a.id, c.id])

        state.sendToBack()
        XCTAssertEqual(state.annotations.map(\.id), [a.id, b.id, c.id])
    }

    // MARK: - Counter sequencing

    func testCounterSequenceContinuesFromMax() {
        let state = makeState()
        XCTAssertEqual(state.nextCounterValue, 1)
        var first = Annotation.make(kind: .counter, frame: .zero, defaults: state.defaults)
        first.counterValue = 1
        var third = Annotation.make(kind: .counter, frame: .zero, defaults: state.defaults)
        third.counterValue = 3
        state.annotations = [first, third]
        XCTAssertEqual(state.nextCounterValue, 4, "next badge continues from the max, even with gaps")
    }

    // MARK: - Composer output

    func testComposerOutputDimensionsIncludePaddingAndChrome() {
        let state = makeState(imageWidth: 100, imageHeight: 80)
        state.padding = 20
        state.frameStyle = .none

        let plain = ImageComposer.compose(state: state)
        XCTAssertEqual(plain.size.width, 140, accuracy: 1)   // 100 + 20×2
        XCTAssertEqual(plain.size.height, 120, accuracy: 1)  // 80 + 20×2

        state.frameStyle = .browser
        let framed = ImageComposer.compose(state: state)
        XCTAssertEqual(framed.size.height, 120 + FrameStyle.browser.chromeHeight, accuracy: 1)
    }

    // MARK: - Exporter

    func testExporterWritesReadablePNG() throws {
        let image = solidImage(width: 64, height: 48)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapture-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(Exporter.write(image, to: url))
        let read = try XCTUnwrap(NSImage(contentsOf: url))
        XCTAssertEqual(read.size.width, 64, accuracy: 1)
        XCTAssertEqual(read.size.height, 48, accuracy: 1)
    }

    // MARK: - Model invariants

    func testCodableColorRoundtrip() {
        let original = CodableColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.9)
        let roundtripped = CodableColor(original.swiftUI)
        XCTAssertEqual(roundtripped.red, original.red, accuracy: 0.01)
        XCTAssertEqual(roundtripped.green, original.green, accuracy: 0.01)
        XCTAssertEqual(roundtripped.blue, original.blue, accuracy: 0.01)
        XCTAssertEqual(roundtripped.alpha, original.alpha, accuracy: 0.01)
    }

    func testFrameStyleChromeHeights() {
        XCTAssertEqual(FrameStyle.none.chromeHeight, 0)
        XCTAssertGreaterThan(FrameStyle.macOS.chromeHeight, 0)
        XCTAssertGreaterThan(FrameStyle.browser.chromeHeight, FrameStyle.macOS.chromeHeight)
    }

    // MARK: - Canvas coordinate mapping (export must match the editor 1:1)

    private func layout(displayScale: CGFloat, origin: CGPoint = .zero) -> CanvasLayout {
        // image 1000x800, padding 40 → native canvas 1080x880, imageRect (40,40,1000,800).
        CanvasLayout(
            canvasSize: CGSize(width: 1080, height: 880),
            imageRect: CGRect(x: 40, y: 40, width: 1000, height: 800),
            viewSize: CGSize(width: 1400, height: 1000),
            canvasOrigin: origin,
            displayScale: displayScale
        )
    }

    func testToCanvasToViewRoundtrip() {
        let l = layout(displayScale: 0.37, origin: CGPoint(x: 120, y: 60))
        let viewPoint = CGPoint(x: 423, y: 311)
        let back = l.toView(l.toCanvas(viewPoint))
        XCTAssertEqual(back.x, viewPoint.x, accuracy: 0.0001)
        XCTAssertEqual(back.y, viewPoint.y, accuracy: 0.0001)
    }

    /// The crux of the export-parity fix: a click at the displayed image's centre
    /// must resolve to the same NATIVE canvas point regardless of the editor's
    /// fit-scale — so the annotation the editor stores renders identically when
    /// the exporter re-lays it out at displayScale = 1.
    func testCanvasPointIsScaleIndependent() {
        for scale: CGFloat in [1.0, 0.5, 0.37, 0.25] {
            let l = layout(displayScale: scale, origin: CGPoint(x: 70, y: 30))
            // Centre of the displayed image in view coordinates.
            let imgCenterView = CGPoint(
                x: l.canvasOrigin.x + (l.imageRect.midX) * scale,
                y: l.canvasOrigin.y + (l.imageRect.midY) * scale
            )
            let native = l.toCanvas(imgCenterView)
            // Always the native image centre (540, 440), independent of scale.
            XCTAssertEqual(native.x, 540, accuracy: 0.001, "scale \(scale)")
            XCTAssertEqual(native.y, 440, accuracy: 0.001, "scale \(scale)")
        }
    }

    // MARK: - Export placement (pixel-level)

    /// Bounding box of red-ish pixels, in top-left (canvas) origin pixel coords.
    private func redBBox(_ cg: CGImage) -> CGRect? {
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, maxX = -1, minYb = h, maxYb = -1
        for yb in 0..<h {
            for x in 0..<w {
                let i = (yb * w + x) * 4
                if buf[i] > 150 && buf[i + 1] < 100 && buf[i + 2] < 100 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minYb = min(minYb, yb); maxYb = max(maxYb, yb)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        // Buffer rows are top-left origin here (row 0 = visual top).
        return CGRect(x: minX, y: minYb, width: maxX - minX + 1, height: maxYb - minYb + 1)
    }

    /// The exported image must place an annotation at its image position — this is
    /// the user-visible "copy matches the editor 1:1" guarantee, end to end.
    func testExportPlacesAnnotationAtImagePosition() {
        let state = makeState(imageWidth: 600, imageHeight: 400)
        state.background = .solid(CodableColor(.white))
        state.padding = 30
        state.shadowEnabled = false

        // Solid red rect at image-local (100,80) size 200x150 → canvas (130,110,...).
        var ann = Annotation.make(kind: .rectangle,
                                  frame: CGRect(x: 130, y: 110, width: 200, height: 150),
                                  defaults: state.defaults)
        ann.color = CodableColor(.red)
        ann.fillColor = CodableColor(.red)
        ann.fillOpacity = 1.0
        ann.strokeWidth = 0
        ann.cornerRadius = 0
        ann.shadowEnabled = false
        state.annotations = [ann]

        let out = ImageComposer.compose(state: state)
        guard let cg = out.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return XCTFail("compose produced no CGImage")
        }
        let s = CGFloat(cg.width) / (600 + 60)   // output pixels per canvas point
        guard let bbox = redBBox(cg) else { return XCTFail("no red pixels found in export") }

        XCTAssertEqual(bbox.minX, 130 * s, accuracy: 5 * s)
        XCTAssertEqual(bbox.minY, 110 * s, accuracy: 5 * s)
        XCTAssertEqual(bbox.width, 200 * s, accuracy: 8 * s)
        XCTAssertEqual(bbox.height, 150 * s, accuracy: 8 * s)
    }

    /// Every annotation kind must compose without crashing and yield the right
    /// canvas dimensions (smoke test for the whole export path post-refactor).
    // MARK: - GIF encoding

    private func solidFrame(_ color: NSColor, at t: Double, size: Int = 24) -> GIFRecorder.Frame {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
        color.setFill(); NSRect(x: 0, y: 0, width: size, height: size).fill()
        NSGraphicsContext.restoreGraphicsState()
        return GIFRecorder.Frame(data: rep.representation(using: .png, properties: [:])!, time: t)
    }

    func testGIFEncoderProducesLoopingAnimatedGIF() {
        let frames = [solidFrame(.red, at: 0), solidFrame(.green, at: 0.1), solidFrame(.blue, at: 0.2)]
        guard let data = GIFEncoder.encode(frames: frames),
              let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            return XCTFail("encode produced no GIF")
        }
        XCTAssertEqual(CGImageSourceGetType(src) as String?, UTType.gif.identifier)
        XCTAssertEqual(CGImageSourceGetCount(src), 3)

        let props = CGImageSourceCopyProperties(src, nil) as? [CFString: Any]
        let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        XCTAssertEqual(gif?[kCGImagePropertyGIFLoopCount] as? Int, 0)   // 0 = infinite
    }

    func testGIFEncoderEmptyReturnsNil() {
        XCTAssertNil(GIFEncoder.encode(frames: []))
    }

    func testGIFQualityScalesWithSlider() {
        let region = CGSize(width: 800, height: 600)
        let lo = GIFQuality.pixelSize(regionPoints: region, quality: 0.0, retinaScale: 2)
        let hi = GIFQuality.pixelSize(regionPoints: region, quality: 1.0, retinaScale: 2)
        XCTAssertGreaterThan(hi.width, lo.width)                       // sharper = more pixels
        XCTAssertGreaterThan(GIFQuality.fps(1.0), GIFQuality.fps(0.0)) // and higher fps
        XCTAssertGreaterThan(
            GIFQuality.estimatedRange(regionPoints: region, quality: 1.0, retinaScale: 2).high,
            GIFQuality.estimatedRange(regionPoints: region, quality: 0.0, retinaScale: 2).high)
        // Longest-edge cap holds even for a huge region at max quality.
        let huge = GIFQuality.pixelSize(regionPoints: CGSize(width: 4000, height: 3000), quality: 1.0, retinaScale: 2)
        XCTAssertLessThanOrEqual(max(huge.width, huge.height), GIFQuality.longestEdgeCap)
    }

    func testComposeHandlesAllAnnotationKinds() {
        let state = makeState(imageWidth: 600, imageHeight: 400)
        var anns: [Annotation] = []
        func add(_ kind: Annotation.Kind, _ frame: CGRect, _ mutate: ((inout Annotation) -> Void)? = nil) {
            var a = Annotation.make(kind: kind, frame: frame, defaults: state.defaults,
                                    image: kind == .image ? ImageRef(solidImage(width: 100, height: 100)) : nil)
            mutate?(&a)
            anns.append(a)
        }
        add(.rectangle, CGRect(x: 40, y: 40, width: 80, height: 60))
        add(.ellipse,   CGRect(x: 140, y: 40, width: 80, height: 60))
        add(.triangle,  CGRect(x: 240, y: 40, width: 80, height: 60))
        add(.line,      CGRect(x: 40, y: 140, width: 80, height: 40))
        add(.arrow,     CGRect(x: 140, y: 140, width: 80, height: 40))
        add(.pen,       CGRect(x: 240, y: 140, width: 80, height: 40)) {
            $0.points = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0)]
        }
        add(.text,      CGRect(x: 40, y: 220, width: 120, height: 30)) { $0.text = "Hello" }
        add(.counter,   CGRect(x: 200, y: 220, width: 32, height: 32))
        add(.blur,      CGRect(x: 260, y: 220, width: 80, height: 60))
        add(.highlight, CGRect(x: 40, y: 300, width: 200, height: 60))
        add(.magnifier, CGRect(x: 300, y: 300, width: 70, height: 70)) { $0.zoom = 2.5 }
        add(.image,     CGRect(x: 420, y: 300, width: 100, height: 80))
        state.annotations = anns

        let out = ImageComposer.compose(state: state)
        XCTAssertEqual(out.size.width, 600 + state.padding * 2, accuracy: 1)
        XCTAssertEqual(out.size.height, 400 + state.padding * 2, accuracy: 1)
        XCTAssertNotNil(out.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }
}
