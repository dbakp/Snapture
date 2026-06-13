import SwiftUI
import AppKit

enum Tool: String, CaseIterable, Identifiable {
    case select, crop, rectangle, ellipse, triangle, line, arrow, pen, text, counter, magnifier, blur, highlight
    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .select:    return "cursorarrow"
        case .crop:      return "crop"
        case .rectangle: return "rectangle"
        case .ellipse:   return "circle"
        case .triangle:  return "triangle"
        case .line:      return "line.diagonal"
        case .arrow:     return "arrow.up.right"
        case .pen:       return "scribble"
        case .text:      return "textformat"
        case .counter:   return "1.circle"
        case .magnifier: return "plus.magnifyingglass"
        case .blur:      return "drop.halffull"
        case .highlight: return "rectangle.dashed"
        }
    }

    var displayName: String {
        switch self {
        case .select:    return "Select"
        case .crop:      return "Crop"
        case .rectangle: return "Rectangle"
        case .ellipse:   return "Ellipse"
        case .triangle:  return "Triangle"
        case .line:      return "Line"
        case .arrow:     return "Arrow"
        case .pen:       return "Pen"
        case .text:      return "Text"
        case .counter:   return "Step badge"
        case .magnifier: return "Magnifier"
        case .blur:      return "Blur"
        case .highlight: return "Highlight"
        }
    }

    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .select:    return "v"
        case .crop:      return "c"
        case .rectangle: return "r"
        case .ellipse:   return "o"
        case .triangle:  return "y"
        case .line:      return "l"
        case .arrow:     return "a"
        case .pen:       return "p"
        case .text:      return "t"
        case .counter:   return "n"
        case .magnifier: return "m"
        case .blur:      return "b"
        case .highlight: return "h"
        }
    }

    var annotationKind: Annotation.Kind? {
        switch self {
        case .rectangle: return .rectangle
        case .ellipse:   return .ellipse
        case .triangle:  return .triangle
        case .line:      return .line
        case .arrow:     return .arrow
        case .pen:       return .pen
        case .text:      return .text
        case .counter:   return .counter
        case .magnifier: return .magnifier
        case .blur:      return .blur
        case .highlight: return .highlight
        case .select, .crop: return nil
        }
    }
}

/// Decorative window chrome rendered above the screenshot in the composition.
enum FrameStyle: String, CaseIterable, Identifiable {
    case none, macOS, browser
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:    return "None"
        case .macOS:   return "macOS"
        case .browser: return "Browser"
        }
    }

    /// Height of the chrome bar in image points (0 when no chrome).
    var chromeHeight: CGFloat {
        switch self {
        case .none:    return 0
        case .macOS:   return 36
        case .browser: return 44
        }
    }
}

/// A complete snapshot of mutable editor state, used by the undo/redo stack.
private struct EditorSnapshot: Equatable {
    var croppedImage: NSImage
    var annotations: [Annotation]
    var background: BackgroundStyle
    var padding: CGFloat
    var cornerRadius: CGFloat
    var shadowEnabled: Bool
    var shadowRadius: CGFloat
    var shadowOpacity: Double
    var frameStyle: FrameStyle
    var selectedAnnotationID: UUID?

    static func == (l: EditorSnapshot, r: EditorSnapshot) -> Bool {
        l.croppedImage === r.croppedImage &&
        l.annotations == r.annotations &&
        l.background == r.background &&
        l.padding == r.padding &&
        l.cornerRadius == r.cornerRadius &&
        l.shadowEnabled == r.shadowEnabled &&
        l.shadowRadius == r.shadowRadius &&
        l.shadowOpacity == r.shadowOpacity &&
        l.frameStyle == r.frameStyle &&
        l.selectedAnnotationID == r.selectedAnnotationID
    }
}

@MainActor
final class EditorState: ObservableObject {
    let originalImage: NSImage
    @Published var croppedImage: NSImage

    @Published var tool: Tool = .select
    @Published var background: BackgroundStyle
    @Published var padding: CGFloat
    @Published var cornerRadius: CGFloat
    @Published var shadowEnabled: Bool
    @Published var shadowRadius: CGFloat = 24
    @Published var shadowOpacity: Double = 0.35

    @Published var frameStyle: FrameStyle = .none

    @Published var annotations: [Annotation] = []
    @Published var selectedAnnotationID: UUID?
    @Published var defaults = AnnotationDefaults()

    @Published var pendingCrop: CGRect?    // image-space rect being drawn

    /// Chrome bar height in image points for the current frame style.
    var chromeHeight: CGFloat { frameStyle.chromeHeight }

    /// Next number for a newly placed step badge.
    var nextCounterValue: Int {
        (annotations.filter { $0.kind == .counter }.map(\.counterValue).max() ?? 0) + 1
    }

    // Undo/redo
    private var undoStack: [EditorSnapshot] = []
    private var redoStack: [EditorSnapshot] = []
    private let maxUndoDepth = 80

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    init(image: NSImage, preferences: Preferences) {
        self.originalImage = image
        self.croppedImage = image
        self.padding = CGFloat(preferences.defaultPadding)
        self.cornerRadius = CGFloat(preferences.defaultCornerRadius)
        self.shadowEnabled = preferences.defaultShadowEnabled
        if let preset = BackgroundPresets.all.first(where: { "gradient.\($0.id)" == preferences.defaultBackground }) {
            self.background = preset.style
        } else {
            self.background = BackgroundPresets.all.first { $0.id == "indigo" }?.style ?? .transparent
        }
    }

    var selectedAnnotation: Annotation? {
        guard let id = selectedAnnotationID else { return nil }
        return annotations.first { $0.id == id }
    }

    func updateSelected(_ mutate: (inout Annotation) -> Void) {
        guard let id = selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        var copy = annotations[index]
        mutate(&copy)
        annotations[index] = copy
    }

    func update(_ id: UUID, _ mutate: (inout Annotation) -> Void) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        var copy = annotations[index]
        mutate(&copy)
        annotations[index] = copy
    }

    func add(_ annotation: Annotation) {
        annotations.append(annotation)
        selectedAnnotationID = annotation.id
    }

    func deleteSelected() {
        guard let id = selectedAnnotationID else { return }
        snapshot()
        annotations.removeAll { $0.id == id }
        selectedAnnotationID = nil
    }

    /// Apply a crop in image-space, replacing croppedImage.
    func applyCrop(rect: CGRect) {
        let imageSize = croppedImage.size
        let clamped = rect.intersection(CGRect(origin: .zero, size: imageSize))
        guard clamped.width > 4, clamped.height > 4 else { return }

        guard let cg = croppedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let scale = CGFloat(cg.width) / imageSize.width
        let pixelRect = CGRect(
            x: clamped.minX * scale,
            y: clamped.minY * scale,
            width: clamped.width * scale,
            height: clamped.height * scale
        )
        guard let cropped = cg.cropping(to: pixelRect) else { return }
        let nsImage = NSImage(cgImage: cropped, size: NSSize(width: clamped.width, height: clamped.height))
        snapshot()
        self.croppedImage = nsImage
        self.annotations = annotations.map { ann in
            var a = ann
            // movedBy preserves negative sizes (arrow direction); offsetBy would standardize.
            a.frame = ann.frame.movedBy(dx: -clamped.minX, dy: -clamped.minY)
            return a
        }
        self.pendingCrop = nil
    }

    func resetCrop() {
        guard croppedImage !== originalImage else { return }
        snapshot()
        self.croppedImage = originalImage
    }

    // MARK: - Z-order

    func bringForward() {
        guard let id = selectedAnnotationID,
              let i = annotations.firstIndex(where: { $0.id == id }),
              i < annotations.count - 1 else { return }
        snapshot()
        annotations.swapAt(i, i + 1)
    }

    func sendBackward() {
        guard let id = selectedAnnotationID,
              let i = annotations.firstIndex(where: { $0.id == id }),
              i > 0 else { return }
        snapshot()
        annotations.swapAt(i, i - 1)
    }

    func bringToFront() {
        guard let id = selectedAnnotationID,
              let i = annotations.firstIndex(where: { $0.id == id }),
              i < annotations.count - 1 else { return }
        snapshot()
        let ann = annotations.remove(at: i)
        annotations.append(ann)
    }

    func sendToBack() {
        guard let id = selectedAnnotationID,
              let i = annotations.firstIndex(where: { $0.id == id }),
              i > 0 else { return }
        snapshot()
        let ann = annotations.remove(at: i)
        annotations.insert(ann, at: 0)
    }

    // MARK: - Paste

    /// Returns true if an image was pasted from the clipboard as a new layer.
    @discardableResult
    func pasteImageFromClipboard(intoCanvasSize canvasSize: CGSize) -> Bool {
        let pb = NSPasteboard.general
        guard let image = NSImage(pasteboard: pb) else { return false }

        snapshot()
        // Fit comfortably inside the canvas: max 60% of either dimension.
        let maxW = canvasSize.width * 0.6
        let maxH = canvasSize.height * 0.6
        let originalSize = image.size
        let scale = min(maxW / originalSize.width, maxH / originalSize.height, 1.0)
        let size = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)
        let origin = CGPoint(x: (canvasSize.width - size.width) / 2,
                             y: (canvasSize.height - size.height) / 2)
        let frame = CGRect(origin: origin, size: size)

        let ann = Annotation.make(kind: .image, frame: frame, defaults: defaults, image: ImageRef(image))
        annotations.append(ann)
        selectedAnnotationID = ann.id
        return true
    }

    // MARK: - Undo / Redo

    /// Capture the current state and push it onto the undo stack.
    /// Call this BEFORE any mutating operation that should be undoable.
    func snapshot() {
        let snap = currentSnapshot()
        if undoStack.last == snap { return }   // de-dupe consecutive identical snapshots
        undoStack.append(snap)
        if undoStack.count > maxUndoDepth { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    /// Removes the most recently pushed undo state. Use to back out a snapshot
    /// when the action that prompted it didn't actually change state.
    func popLastSnapshot() {
        _ = undoStack.popLast()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot())
        apply(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot())
        apply(next)
    }

    private func currentSnapshot() -> EditorSnapshot {
        EditorSnapshot(
            croppedImage: croppedImage,
            annotations: annotations,
            background: background,
            padding: padding,
            cornerRadius: cornerRadius,
            shadowEnabled: shadowEnabled,
            shadowRadius: shadowRadius,
            shadowOpacity: shadowOpacity,
            frameStyle: frameStyle,
            selectedAnnotationID: selectedAnnotationID
        )
    }

    private func apply(_ snap: EditorSnapshot) {
        self.croppedImage = snap.croppedImage
        self.annotations = snap.annotations
        self.background = snap.background
        self.padding = snap.padding
        self.cornerRadius = snap.cornerRadius
        self.shadowEnabled = snap.shadowEnabled
        self.shadowRadius = snap.shadowRadius
        self.shadowOpacity = snap.shadowOpacity
        self.frameStyle = snap.frameStyle
        self.selectedAnnotationID = snap.selectedAnnotationID
    }
}
