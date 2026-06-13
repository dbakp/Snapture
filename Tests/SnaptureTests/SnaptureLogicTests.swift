import XCTest
import AppKit
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
}
