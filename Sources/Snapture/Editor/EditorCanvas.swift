import SwiftUI
import AppKit

struct CanvasLayout: Equatable {
    let canvasSize: CGSize       // outer "page" size (image + padding)
    let imageRect: CGRect        // screenshot rect within canvas, origin top-left
    let viewSize: CGSize         // size of the visible editor area
    let canvasOrigin: CGPoint    // top-left of canvas within view (for centering)

    /// Map a point in view coordinates → canvas coordinates.
    func toCanvas(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - canvasOrigin.x, y: point.y - canvasOrigin.y)
    }
}

struct EditorCanvas: View {
    @EnvironmentObject private var state: EditorState
    @State private var dragStart: CGPoint?
    @State private var dragKind: DragKind = .none
    @State private var initialAnnotationFrame: CGRect = .zero
    @State private var editingTextID: UUID?
    /// Mirror of the text being typed in the inline editor, lifted here so
    /// the commit-on-tap-outside backdrop can see the current value.
    @State private var editingText: String = ""
    /// Absolute canvas-space points collected while drawing a pen stroke.
    @State private var penAbsolutePoints: [CGPoint] = []

    enum DragKind {
        case none, createAnnotation, moveAnnotation(UUID), resizeAnnotation(UUID, Handle), cropDraw
    }

    enum Handle {
        case topLeft, topRight, bottomLeft, bottomRight
        case arrowStart, arrowEnd       // arrow-specific endpoint handles
    }

    var body: some View {
        GeometryReader { geo in
            let layout = computeLayout(in: geo.size)
            ZStack(alignment: .topLeading) {
                Color.clear
                CompositionView(state: state, layout: layout, hiddenAnnotationID: editingTextID)
                    .equatable()
                    .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
                    .offset(x: layout.canvasOrigin.x, y: layout.canvasOrigin.y)
                    .allowsHitTesting(false)

                if let selected = state.selectedAnnotation {
                    SelectionHandlesView(annotation: selected, canvasOffset: layout.canvasOrigin)
                        .allowsHitTesting(false)
                }

                if let crop = state.pendingCrop {
                    CropOverlayView(imageRect: layout.imageRect.offsetBy(dx: layout.canvasOrigin.x, dy: layout.canvasOrigin.y),
                                    cropRect: crop.offsetBy(dx: layout.imageRect.minX + layout.canvasOrigin.x,
                                                            dy: layout.imageRect.minY + layout.canvasOrigin.y))
                        .allowsHitTesting(false)
                }

                if editingTextID == nil {
                    // Normal mode: gesture surface receives drag-to-create / click-to-select.
                    Color.white.opacity(0.0001)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in handleChanged(value: value, layout: layout) }
                                .onEnded   { value in handleEnded(value: value, layout: layout) }
                        )
                        .onTapGesture(count: 2) { location in handleDoubleTap(at: location, layout: layout) }
                } else {
                    // Editing mode: tap anywhere outside the text field to commit.
                    Color.white.opacity(0.0001)
                        .contentShape(Rectangle())
                        .onTapGesture { commitTextEditing() }
                }

                // Text editor renders LAST so it sits on top of the gesture/backdrop
                // surface and actually receives mouse clicks + keyboard input.
                if let id = editingTextID,
                   let ann = state.annotations.first(where: { $0.id == id }) {
                    TextEditOverlay(annotation: ann, layout: layout, text: $editingText) {
                        commitTextEditing()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Layout

    private func computeLayout(in viewSize: CGSize) -> CanvasLayout {
        let image = state.croppedImage.size
        let padding = state.padding
        let chromeH = state.chromeHeight
        let canvasW = image.width + padding * 2
        let canvasH = image.height + chromeH + padding * 2

        let scale = min(
            (viewSize.width  - 40) / canvasW,
            (viewSize.height - 40) / canvasH,
            1.0
        )
        let displayedCanvasW = canvasW * scale
        let displayedCanvasH = canvasH * scale
        let imageRect = CGRect(x: padding * scale, y: (padding + chromeH) * scale,
                               width: image.width * scale, height: image.height * scale)

        return CanvasLayout(
            canvasSize: CGSize(width: displayedCanvasW, height: displayedCanvasH),
            imageRect: imageRect,
            viewSize: viewSize,
            canvasOrigin: CGPoint(
                x: (viewSize.width  - displayedCanvasW) / 2,
                y: (viewSize.height - displayedCanvasH) / 2
            )
        )
    }

    // MARK: - Gesture handling

    private func handleChanged(value: DragGesture.Value, layout: CanvasLayout) {
        let canvasPoint = layout.toCanvas(value.location)
        let startPoint  = layout.toCanvas(value.startLocation)

        if dragStart == nil {
            dragStart = startPoint
            beginDrag(at: startPoint, layout: layout)
        }

        let rect = CGRect(
            x: min(startPoint.x, canvasPoint.x),
            y: min(startPoint.y, canvasPoint.y),
            width: abs(canvasPoint.x - startPoint.x),
            height: abs(canvasPoint.y - startPoint.y)
        )

        switch dragKind {
        case .none: break
        case .createAnnotation:
            guard let id = state.selectedAnnotationID,
                  let current = state.annotations.first(where: { $0.id == id }) else { break }
            if current.kind == .pen {
                // Accumulate the stroke; store points normalized to the bounding box.
                penAbsolutePoints.append(canvasPoint)
                let xs = penAbsolutePoints.map(\.x)
                let ys = penAbsolutePoints.map(\.y)
                let bbox = CGRect(
                    x: xs.min() ?? canvasPoint.x,
                    y: ys.min() ?? canvasPoint.y,
                    width: max((xs.max() ?? 0) - (xs.min() ?? 0), 0.001),
                    height: max((ys.max() ?? 0) - (ys.min() ?? 0), 0.001)
                )
                let normalized = penAbsolutePoints.map {
                    CGPoint(x: ($0.x - bbox.minX) / bbox.width,
                            y: ($0.y - bbox.minY) / bbox.height)
                }
                state.update(id) { $0.frame = bbox; $0.points = normalized }
            } else if current.kind.isLinear {
                state.update(id) { ann in
                    ann.frame = CGRect(x: startPoint.x, y: startPoint.y,
                                       width: canvasPoint.x - startPoint.x,
                                       height: canvasPoint.y - startPoint.y)
                }
            } else if current.kind == .counter {
                // Badge follows the cursor (fixed size, centered on it).
                state.update(id) { ann in
                    ann.frame = CGRect(x: canvasPoint.x - ann.frame.width / 2,
                                       y: canvasPoint.y - ann.frame.height / 2,
                                       width: ann.frame.width, height: ann.frame.height)
                }
            } else {
                state.update(id) { $0.frame = rect }
            }
        case .moveAnnotation(let id):
            let dx = canvasPoint.x - startPoint.x
            let dy = canvasPoint.y - startPoint.y
            // movedBy, NOT offsetBy: offsetBy standardizes the rect, which would
            // flip a left/up-pointing arrow's direction while dragging it.
            state.update(id) { $0.frame = initialAnnotationFrame.movedBy(dx: dx, dy: dy) }
        case .resizeAnnotation(let id, let handle):
            state.update(id) { ann in
                let shouldLockAspect = NSEvent.modifierFlags.contains(.shift)
                    && ann.kind == .image
                    && initialAnnotationFrame.width > 0.001
                    && initialAnnotationFrame.height > 0.001
                let aspect: CGFloat? = shouldLockAspect
                    ? initialAnnotationFrame.width / initialAnnotationFrame.height
                    : nil
                ann.frame = resize(initialAnnotationFrame, handle: handle, to: canvasPoint, aspectLock: aspect)
            }
        case .cropDraw:
            let inImage = CGRect(
                x: rect.minX - layout.imageRect.minX,
                y: rect.minY - layout.imageRect.minY,
                width: rect.width, height: rect.height
            )
            let clamped = inImage.intersection(CGRect(origin: .zero, size: state.croppedImage.size).applying(.init(scaleX: scaleForImage(layout), y: scaleForImage(layout))))
            state.pendingCrop = clamped
        }
    }

    private func handleEnded(value: DragGesture.Value, layout: CanvasLayout) {
        defer {
            dragStart = nil
            dragKind = .none
        }
        // If it's effectively a click (no drag distance), and the tool is text, place a text annotation.
        let canvasPoint = layout.toCanvas(value.location)
        let startPoint  = layout.toCanvas(value.startLocation)
        let dragDistance = hypot(canvasPoint.x - startPoint.x, canvasPoint.y - startPoint.y)

        if case .createAnnotation = dragKind, state.tool == .text, dragDistance < 3 {
            let frame = CGRect(x: canvasPoint.x, y: canvasPoint.y - 14, width: 180, height: 30)
            let ann = Annotation.make(kind: .text, frame: frame, defaults: state.defaults)
            // Replace the zero-size placeholder we started on mouseDown.
            if let id = state.selectedAnnotationID,
               state.annotations.first(where: { $0.id == id })?.kind == .text {
                state.annotations.removeAll { $0.id == id }
            }
            state.add(ann)
            startTextEditing(ann)
            return
        }

        // A pen "stroke" that never moved is invisible — discard it.
        if case .createAnnotation = dragKind,
           let id = state.selectedAnnotationID,
           let ann = state.annotations.first(where: { $0.id == id }),
           ann.kind == .pen, penAbsolutePoints.count < 2 {
            state.annotations.removeAll { $0.id == id }
            state.selectedAnnotationID = nil
            state.popLastSnapshot()
        }
        penAbsolutePoints = []

        if case .createAnnotation = dragKind,
           let id = state.selectedAnnotationID,
           let ann = state.annotations.first(where: { $0.id == id }),
           !ann.kind.isLinear, ann.kind != .pen, ann.kind != .counter,
           (ann.frame.width < 5 || ann.frame.height < 5) {
            state.annotations.removeAll { $0.id == id }
            state.selectedAnnotationID = nil
            state.popLastSnapshot()    // back out the snapshot for the canceled create
        }

        // Move / resize that ended up at the same frame? Drop the snapshot.
        if case .moveAnnotation(let id) = dragKind,
           let ann = state.annotations.first(where: { $0.id == id }),
           ann.frame == initialAnnotationFrame {
            state.popLastSnapshot()
        }
        if case .resizeAnnotation(let id, _) = dragKind,
           let ann = state.annotations.first(where: { $0.id == id }),
           ann.frame == initialAnnotationFrame {
            state.popLastSnapshot()
        }
    }

    private func handleDoubleTap(at location: CGPoint, layout: CanvasLayout) {
        let canvasPoint = layout.toCanvas(location)
        if let hit = hitTest(canvasPoint: canvasPoint), hit.kind == .text {
            state.selectedAnnotationID = hit.id
            startTextEditing(hit)
        }
    }

    private func startTextEditing(_ annotation: Annotation) {
        editingText = annotation.text
        editingTextID = annotation.id
    }

    /// Commit (or discard, if empty) the in-progress text edit.
    /// Called from: Enter / Escape inside the TextField, tap outside, or focus loss.
    private func commitTextEditing() {
        guard let id = editingTextID else { return }
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // Don't leave invisible empty text layers lying around.
            state.annotations.removeAll { $0.id == id }
            state.selectedAnnotationID = nil
            state.popLastSnapshot()
        } else {
            state.update(id) { $0.text = editingText }
        }
        editingTextID = nil
        editingText = ""
    }

    private func beginDrag(at canvasPoint: CGPoint, layout: CanvasLayout) {
        // Smart click: clicking on an existing annotation selects/grabs it,
        // regardless of which tool is active (except crop, which is modal).
        if state.tool != .crop, let hit = hitTest(canvasPoint: canvasPoint) {
            state.selectedAnnotationID = hit.id
            if let handle = hitTestHandle(canvasPoint: canvasPoint, annotation: hit) {
                state.snapshot()    // before resize
                dragKind = .resizeAnnotation(hit.id, handle)
            } else {
                state.snapshot()    // before move
                dragKind = .moveAnnotation(hit.id)
            }
            initialAnnotationFrame = hit.frame
            return
        }

        if state.tool == .select {
            state.selectedAnnotationID = nil
            dragKind = .none
            return
        }

        if state.tool == .crop {
            dragKind = .cropDraw
            state.pendingCrop = .zero
            return
        }

        // Empty space + creation tool → create a new annotation.
        guard let kind = state.tool.annotationKind else { dragKind = .none; return }
        state.snapshot()    // before create

        switch kind {
        case .counter:
            let d: CGFloat = 32
            var ann = Annotation.make(
                kind: .counter,
                frame: CGRect(x: canvasPoint.x - d / 2, y: canvasPoint.y - d / 2, width: d, height: d),
                defaults: state.defaults
            )
            ann.counterValue = state.nextCounterValue
            state.add(ann)
        case .pen:
            penAbsolutePoints = [canvasPoint]
            let ann = Annotation.make(kind: .pen,
                                      frame: CGRect(origin: canvasPoint, size: .zero),
                                      defaults: state.defaults)
            state.add(ann)
        default:
            let initial = CGRect(x: canvasPoint.x, y: canvasPoint.y, width: 0, height: 0)
            state.add(Annotation.make(kind: kind, frame: initial, defaults: state.defaults))
        }
        dragKind = .createAnnotation
    }

    // MARK: - Hit testing

    private func hitTest(canvasPoint: CGPoint) -> Annotation? {
        for ann in state.annotations.reversed() {
            let frame = ann.frame.insetBy(dx: -6, dy: -6)
            if frame.contains(canvasPoint) { return ann }
            if ann.kind.isLinear {
                if distanceToArrowLine(ann: ann, point: canvasPoint) < 10 { return ann }
            }
        }
        return nil
    }

    private func hitTestHandle(canvasPoint: CGPoint, annotation: Annotation) -> Handle? {
        // Arrows use two endpoint handles (tail/tip), NOT corner handles.
        // frame.origin = tail (start), frame.origin + frame.size = tip (end).
        if annotation.kind.isLinear {
            let start = annotation.arrowTail
            let end = annotation.arrowTip

            // 1) Direct hit on the visible 9pt endpoint dot, with generous forgiveness.
            let handleRadius: CGFloat = 18
            let dStart = hypot(start.x - canvasPoint.x, start.y - canvasPoint.y)
            let dEnd   = hypot(end.x   - canvasPoint.x, end.y   - canvasPoint.y)
            if dStart < handleRadius && dStart <= dEnd { return .arrowStart }
            if dEnd   < handleRadius && dEnd   <  dStart { return .arrowEnd }

            // 2) Click landed on the arrow's line itself? Classify by where along it:
            //    outer 1/3 near tail → arrowStart, outer 1/3 near tip → arrowEnd,
            //    middle 1/3 → not a handle (fall through to move).
            let dx = end.x - start.x
            let dy = end.y - start.y
            let len2 = dx*dx + dy*dy
            if len2 > 0.01 {
                let tRaw = ((canvasPoint.x - start.x) * dx + (canvasPoint.y - start.y) * dy) / len2
                let t = max(0, min(1, tRaw))
                let projX = start.x + t * dx
                let projY = start.y + t * dy
                let distToLine = hypot(canvasPoint.x - projX, canvasPoint.y - projY)
                if distToLine < 10 {
                    if t < 0.34 { return .arrowStart }
                    if t > 0.66 { return .arrowEnd }
                }
            }
            return nil
        }

        let frame = annotation.frame
        let handles: [(Handle, CGPoint)] = [
            (.topLeft, CGPoint(x: frame.minX, y: frame.minY)),
            (.topRight, CGPoint(x: frame.maxX, y: frame.minY)),
            (.bottomLeft, CGPoint(x: frame.minX, y: frame.maxY)),
            (.bottomRight, CGPoint(x: frame.maxX, y: frame.maxY))
        ]
        for (h, p) in handles {
            if hypot(p.x - canvasPoint.x, p.y - canvasPoint.y) < 12 { return h }
        }
        return nil
    }

    private func resize(_ initial: CGRect, handle: Handle, to point: CGPoint, aspectLock: CGFloat? = nil) -> CGRect {
        var f = initial
        switch handle {
        case .topLeft:
            f.origin.x = point.x
            f.origin.y = point.y
            f.size.width  = initial.maxX - point.x
            f.size.height = initial.maxY - point.y
        case .topRight:
            f.origin.y = point.y
            f.size.width  = point.x - initial.minX
            f.size.height = initial.maxY - point.y
        case .bottomLeft:
            f.origin.x = point.x
            f.size.width  = initial.maxX - point.x
            f.size.height = point.y - initial.minY
        case .bottomRight:
            f.size.width  = point.x - initial.minX
            f.size.height = point.y - initial.minY
        case .arrowStart:
            // Tip stays as pivot. Tail (frame.origin) moves with the cursor.
            // size.width/height keep the sign — initial.width would return abs
            // and mirror the tip the moment the arrow points left or up.
            let tip = CGPoint(x: initial.origin.x + initial.size.width,
                              y: initial.origin.y + initial.size.height)
            f.origin = point
            f.size = CGSize(width: tip.x - point.x, height: tip.y - point.y)
        case .arrowEnd:
            // Tail stays as pivot. Tip moves with the cursor.
            let tail = initial.origin
            f.origin = tail
            f.size = CGSize(width: point.x - tail.x, height: point.y - tail.y)
        }

        // Aspect-lock pass — applies only to corner handles (image resize use case).
        if let aspect = aspectLock, aspect > 0,
           initial.width > 0, initial.height > 0,
           f.width > 0, f.height > 0,
           handle != .arrowStart, handle != .arrowEnd {
            let dw = abs(f.width  - initial.width)
            let dh = abs(f.height - initial.height)

            if dw >= dh {
                let newHeight = f.width / aspect
                if handle == .topLeft || handle == .topRight {
                    f.origin.y = initial.maxY - newHeight
                }
                f.size.height = newHeight
            } else {
                let newWidth = f.height * aspect
                if handle == .topLeft || handle == .bottomLeft {
                    f.origin.x = initial.maxX - newWidth
                }
                f.size.width = newWidth
            }
        }
        return f
    }

    private func scaleForImage(_ layout: CanvasLayout) -> CGFloat {
        layout.imageRect.width / state.croppedImage.size.width
    }

    /// Distance from `point` to the arrow's actual line segment (true tail → tip).
    private func distanceToArrowLine(ann: Annotation, point: CGPoint) -> CGFloat {
        let a = ann.arrowTail
        let b = ann.arrowTip
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx*dx + dy*dy
        if len2 == 0 { return hypot(point.x - a.x, point.y - a.y) }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / len2))
        let px = a.x + t*dx, py = a.y + t*dy
        return hypot(point.x - px, point.y - py)
    }
}

// MARK: - Composition view (shared between preview and export)

/// Value-based and Equatable on purpose: the editor re-evaluates its body on
/// every EditorState change (tool switches, selection, hover state), but the
/// composition only needs to re-render when something VISIBLE changed. Wrap
/// usage in `.equatable()` so SwiftUI can skip the whole subtree otherwise.
struct CompositionView: View, @MainActor Equatable {
    let background: BackgroundStyle
    let image: NSImage
    let annotations: [Annotation]
    let cornerRadius: CGFloat
    let shadowEnabled: Bool
    let shadowRadius: CGFloat
    let shadowOpacity: Double
    let frameStyle: FrameStyle
    let layout: CanvasLayout
    let hiddenAnnotationID: UUID?

    @MainActor
    init(state: EditorState, layout: CanvasLayout, hiddenAnnotationID: UUID? = nil) {
        self.background = state.background
        self.image = state.croppedImage
        self.annotations = state.annotations
        self.cornerRadius = state.cornerRadius
        self.shadowEnabled = state.shadowEnabled
        self.shadowRadius = state.shadowRadius
        self.shadowOpacity = state.shadowOpacity
        self.frameStyle = state.frameStyle
        self.layout = layout
        self.hiddenAnnotationID = hiddenAnnotationID
    }

    static func == (l: CompositionView, r: CompositionView) -> Bool {
        l.image === r.image &&
        l.background == r.background &&
        l.annotations == r.annotations &&
        l.cornerRadius == r.cornerRadius &&
        l.shadowEnabled == r.shadowEnabled &&
        l.shadowRadius == r.shadowRadius &&
        l.shadowOpacity == r.shadowOpacity &&
        l.frameStyle == r.frameStyle &&
        l.layout == r.layout &&
        l.hiddenAnnotationID == r.hiddenAnnotationID
    }

    var body: some View {
        let visible = annotations.filter { $0.id != hiddenAnnotationID }
        let highlights = visible.filter { $0.kind == .highlight }
        let nonHighlights = visible.filter { $0.kind != .highlight }

        let imageScale = layout.imageRect.width / max(1, image.size.width)
        let chromeDisplayH = frameStyle.chromeHeight * imageScale

        ZStack(alignment: .topLeading) {
            background.view()
                .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)

            // Screenshot + optional window chrome, clipped and shadowed as one unit.
            VStack(spacing: 0) {
                if frameStyle != .none {
                    WindowChromeBar(style: frameStyle, scale: imageScale)
                        .frame(width: layout.imageRect.width, height: chromeDisplayH)
                }
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: layout.imageRect.width, height: layout.imageRect.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(
                color: shadowEnabled ? .black.opacity(shadowOpacity) : .clear,
                radius: shadowRadius,
                x: 0, y: shadowRadius * 0.4
            )
            .offset(x: layout.imageRect.minX, y: layout.imageRect.minY - chromeDisplayH)

            // Non-highlight annotations in z-order.
            ForEach(nonHighlights) { ann in
                switch ann.kind {
                case .blur:
                    BlurRegionView(annotation: ann, layout: layout, image: image,
                                   cornerRadius: cornerRadius)
                case .magnifier:
                    MagnifierView(annotation: ann, layout: layout, image: image)
                default:
                    AnnotationView(annotation: ann)
                }
            }

            // Highlights all render in ONE backdrop pass on top, so multiple
            // highlights don't compound their dim onto each other.
            if !highlights.isEmpty {
                CombinedHighlightView(highlights: highlights, canvasSize: layout.canvasSize)
            }
        }
        .compositingGroup()
    }
}

/// Fake window titlebar drawn above the screenshot: traffic lights, and a URL
/// pill in browser style. All metrics scale with the displayed image scale so
/// the export at 1:1 looks identical to the preview.
struct WindowChromeBar: View {
    let style: FrameStyle
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 8 * scale) {
            trafficLight(Color(red: 1.00, green: 0.37, blue: 0.34))
            trafficLight(Color(red: 1.00, green: 0.74, blue: 0.18))
            trafficLight(Color(red: 0.20, green: 0.78, blue: 0.27))

            if style == .browser {
                RoundedRectangle(cornerRadius: 8 * scale)
                    .fill(Color.white.opacity(0.85))
                    .frame(height: 24 * scale)
                    .padding(.leading, 10 * scale)
                    .padding(.trailing, 4 * scale)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.925, green: 0.925, blue: 0.93))
        .overlay(alignment: .bottom) {
            Color.black.opacity(0.08).frame(height: max(0.5, scale))
        }
    }

    private func trafficLight(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 12 * scale, height: 12 * scale)
    }
}

/// A single dim layer with every highlight's spotlight rect punched out.
/// Uses the max dim across all highlights so adding a new one never darkens existing ones.
struct CombinedHighlightView: View {
    let highlights: [Annotation]
    let canvasSize: CGSize

    var body: some View {
        let dim = highlights.map { $0.fillOpacity }.max() ?? 0
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(.black.opacity(max(0, min(0.85, dim * 0.75)))))
            ctx.blendMode = .destinationOut
            for hl in highlights {
                ctx.fill(
                    Path(roundedRect: hl.frame.standardized, cornerRadius: max(2, hl.cornerRadius)),
                    with: .color(.black)
                )
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .allowsHitTesting(false)
    }
}

// MARK: - Annotation views

struct AnnotationView: View {
    let annotation: Annotation

    var body: some View {
        switch annotation.kind {
        case .rectangle:
            ZStack {
                annotation.fillColor.swiftUI.opacity(annotation.fillOpacity)
                RoundedRectangle(cornerRadius: annotation.cornerRadius)
                    .stroke(annotation.color.swiftUI, lineWidth: annotation.strokeWidth)
            }
            .frame(width: annotation.frame.width, height: annotation.frame.height)
            .clipShape(RoundedRectangle(cornerRadius: annotation.cornerRadius))
            .modifier(LayerShadow(annotation: annotation))
            .offset(x: annotation.frame.minX, y: annotation.frame.minY)
        case .ellipse:
            ZStack {
                Ellipse().fill(annotation.fillColor.swiftUI.opacity(annotation.fillOpacity))
                Ellipse().stroke(annotation.color.swiftUI, lineWidth: annotation.strokeWidth)
            }
            .frame(width: annotation.frame.width, height: annotation.frame.height)
            .modifier(LayerShadow(annotation: annotation))
            .offset(x: annotation.frame.minX, y: annotation.frame.minY)
        case .triangle:
            ZStack {
                TriangleShape().fill(annotation.fillColor.swiftUI.opacity(annotation.fillOpacity))
                TriangleShape().stroke(annotation.color.swiftUI,
                                       style: StrokeStyle(lineWidth: annotation.strokeWidth, lineJoin: .round))
            }
            .frame(width: annotation.frame.width, height: annotation.frame.height)
            .modifier(LayerShadow(annotation: annotation))
            .offset(x: annotation.frame.minX, y: annotation.frame.minY)
        case .arrow:
            // Map the true tail/tip into the standardized bounding box's local
            // space. No sign conditionals — arrowTail/arrowTip carry direction.
            let bounds = annotation.frame.standardized
            let tail = annotation.arrowTail
            let tip = annotation.arrowTip
            ArrowShape(
                start: CGPoint(x: tail.x - bounds.minX, y: tail.y - bounds.minY),
                end:   CGPoint(x: tip.x  - bounds.minX, y: tip.y  - bounds.minY),
                headSize: max(8, annotation.strokeWidth * 3.5)
            )
            .stroke(annotation.color.swiftUI,
                    style: StrokeStyle(lineWidth: annotation.strokeWidth, lineCap: .round, lineJoin: .round))
            .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
            .offset(x: bounds.minX, y: bounds.minY)
        case .text:
            Text(annotation.text)
                .font(.system(size: annotation.fontSize, weight: .semibold))
                .foregroundStyle(annotation.color.swiftUI)
                .padding(.horizontal, 2)
                .fixedSize()
                .modifier(LayerShadow(annotation: annotation))
                .offset(x: annotation.frame.minX, y: annotation.frame.minY)
        case .image:
            if let imgRef = annotation.image {
                Image(nsImage: imgRef.image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: max(0, annotation.frame.width),
                           height: max(0, annotation.frame.height))
                    .clipShape(RoundedRectangle(cornerRadius: annotation.cornerRadius))
                    .modifier(LayerShadow(annotation: annotation))
                    .offset(x: annotation.frame.minX, y: annotation.frame.minY)
            }
        case .line:
            let bounds = annotation.frame.standardized
            let tail = annotation.arrowTail
            let tip = annotation.arrowTip
            LineShape(
                start: CGPoint(x: tail.x - bounds.minX, y: tail.y - bounds.minY),
                end:   CGPoint(x: tip.x  - bounds.minX, y: tip.y  - bounds.minY)
            )
            .stroke(annotation.color.swiftUI,
                    style: StrokeStyle(lineWidth: annotation.strokeWidth, lineCap: .round))
            .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
            .offset(x: bounds.minX, y: bounds.minY)
        case .pen:
            PenShape(points: annotation.points)
                .stroke(annotation.color.swiftUI,
                        style: StrokeStyle(lineWidth: annotation.strokeWidth, lineCap: .round, lineJoin: .round))
                .frame(width: max(annotation.frame.width, 0.001),
                       height: max(annotation.frame.height, 0.001),
                       alignment: .topLeading)
                .offset(x: annotation.frame.minX, y: annotation.frame.minY)
        case .counter:
            ZStack {
                Circle().fill(annotation.color.swiftUI)
                Text("\(annotation.counterValue)")
                    .font(.system(size: max(10, annotation.frame.height * 0.52), weight: .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.4)
            }
            .frame(width: annotation.frame.width, height: annotation.frame.height)
            .modifier(LayerShadow(annotation: annotation))
            .offset(x: annotation.frame.minX, y: annotation.frame.minY)
        case .magnifier:
            // CompositionView routes magnifier to MagnifierView directly; this is a fallback.
            EmptyView()
        case .blur, .highlight:
            EmptyView()
        }
    }
}

struct LineShape: Shape {
    let start: CGPoint
    let end: CGPoint
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: start)
        p.addLine(to: end)
        return p
    }
}

/// Freehand stroke; points are normalized 0…1 to the frame.
struct PenShape: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: CGPoint(x: first.x * rect.width, y: first.y * rect.height))
        for pt in points.dropFirst() {
            p.addLine(to: CGPoint(x: pt.x * rect.width, y: pt.y * rect.height))
        }
        return p
    }
}

struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Reusable shadow modifier driven by an Annotation's per-layer shadow settings.
struct LayerShadow: ViewModifier {
    let annotation: Annotation
    func body(content: Content) -> some View {
        content.shadow(
            color: annotation.shadowEnabled
                ? Color.black.opacity(annotation.shadowOpacity)
                : .clear,
            radius: annotation.shadowEnabled ? annotation.shadowRadius : 0,
            x: 0,
            y: annotation.shadowEnabled ? annotation.shadowRadius * 0.4 : 0
        )
    }
}

struct ArrowShape: Shape {
    let start: CGPoint
    let end: CGPoint
    let headSize: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let s = CGPoint(x: max(0, min(rect.width, start.x)),
                        y: max(0, min(rect.height, start.y)))
        let e = CGPoint(x: max(0, min(rect.width, end.x)),
                        y: max(0, min(rect.height, end.y)))
        let dx = e.x - s.x, dy = e.y - s.y
        let len = sqrt(dx*dx + dy*dy)
        guard len > 0.1 else { return p }
        let ux = dx / len, uy = dy / len
        let shaftEnd = CGPoint(x: e.x - ux * headSize * 0.6, y: e.y - uy * headSize * 0.6)
        p.move(to: s)
        p.addLine(to: shaftEnd)

        let leftX = e.x - ux * headSize - uy * headSize * 0.5
        let leftY = e.y - uy * headSize + ux * headSize * 0.5
        let rightX = e.x - ux * headSize + uy * headSize * 0.5
        let rightY = e.y - uy * headSize - ux * headSize * 0.5
        p.move(to: CGPoint(x: leftX, y: leftY))
        p.addLine(to: e)
        p.addLine(to: CGPoint(x: rightX, y: rightY))
        return p
    }
}

/// A circular loupe that re-renders the screenshot under it at a higher zoom.
///
/// Performance: we crop ONLY the source region the loupe shows and draw that
/// small image. The old approach drew the entire screenshot (15+ MP for a
/// Retina display) into the Canvas on every redraw — multi-hundred-ms stalls.
struct MagnifierView: View {
    let annotation: Annotation
    let layout: CanvasLayout
    let image: NSImage

    var body: some View {
        let frame = annotation.frame.standardized
        let zoom = max(1.0, annotation.zoom)
        let strokeWidth = max(2, annotation.strokeWidth)

        Canvas { ctx, size in
            ctx.clip(to: Path(ellipseIn: CGRect(origin: .zero, size: size)))
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

            let canvasPtPerImagePt = layout.imageRect.width / max(1, image.size.width)
            let pxPerImagePt = CGFloat(cg.width) / max(1, image.size.width)

            // Loupe centre in image-point coordinates.
            let centerIx = (frame.midX - layout.imageRect.minX) / canvasPtPerImagePt
            let centerIy = (frame.midY - layout.imageRect.minY) / canvasPtPerImagePt

            // The source region (in image pixels) that the loupe magnifies.
            let srcW = size.width  / zoom / canvasPtPerImagePt * pxPerImagePt
            let srcH = size.height / zoom / canvasPtPerImagePt * pxPerImagePt
            let src = CGRect(x: centerIx * pxPerImagePt - srcW / 2,
                             y: centerIy * pxPerImagePt - srcH / 2,
                             width: srcW, height: srcH)

            let bounds = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
            let visible = src.intersection(bounds)
            guard !visible.isEmpty, let crop = cg.cropping(to: visible) else { return }

            // Map the visible part of the source into loupe-local coordinates,
            // so the loupe stays correct when it hangs past the image edge.
            let scaleX = size.width  / src.width
            let scaleY = size.height / src.height
            let dest = CGRect(
                x: (visible.minX - src.minX) * scaleX,
                y: (visible.minY - src.minY) * scaleY,
                width: visible.width * scaleX,
                height: visible.height * scaleY
            )
            ctx.draw(Image(decorative: crop, scale: 1), in: dest)
        }
        .frame(width: frame.width, height: frame.height)
        .overlay(
            ZStack {
                Ellipse()
                    .strokeBorder(annotation.color.swiftUI, lineWidth: strokeWidth)
                Ellipse()
                    .strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5)
            }
        )
        .modifier(LayerShadow(annotation: annotation))
        .offset(x: frame.minX, y: frame.minY)
    }
}

struct BlurRegionView: View {
    let annotation: Annotation
    let layout: CanvasLayout
    let image: NSImage
    let cornerRadius: CGFloat
    @State private var pixelatedImage: NSImage?

    var body: some View {
        Group {
            if annotation.pixelate {
                // Mosaic: pre-downsampled image upscaled with no interpolation.
                Image(nsImage: pixelatedImage ?? image)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: layout.imageRect.width, height: layout.imageRect.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: layout.imageRect.width, height: layout.imageRect.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .blur(radius: annotation.blurRadius, opaque: false)
            }
        }
        .offset(x: layout.imageRect.minX, y: layout.imageRect.minY)
        .mask(
            Rectangle()
                .frame(width: annotation.frame.width, height: annotation.frame.height)
                .position(x: annotation.frame.midX, y: annotation.frame.midY)
        )
        .onAppear { recomputePixelation() }
        .onChange(of: annotation.pixelate) { _, _ in recomputePixelation() }
        .onChange(of: annotation.blurRadius) { _, _ in recomputePixelation() }
        .onChange(of: ObjectIdentifier(image)) { _, _ in recomputePixelation() }
    }

    private func recomputePixelation() {
        guard annotation.pixelate else { pixelatedImage = nil; return }
        // Block size in source pixels ≈ slider value in display points.
        let displayScale = max(0.01, layout.imageRect.width / max(1, image.size.width))
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let pixelsPerPoint = CGFloat(cg.width) / max(1, image.size.width)
        let block = max(4, annotation.blurRadius / displayScale * pixelsPerPoint * 0.5)
        pixelatedImage = Self.pixelate(cg, block: block, pointSize: image.size)
    }

    /// Downsample by `block`, return a tiny image; SwiftUI upscales it with
    /// .interpolation(.none) to produce crisp mosaic squares.
    private static func pixelate(_ cg: CGImage, block: CGFloat, pointSize: NSSize) -> NSImage? {
        let smallW = max(1, Int(CGFloat(cg.width) / block))
        let smallH = max(1, Int(CGFloat(cg.height) / block))
        guard let ctx = CGContext(
            data: nil, width: smallW, height: smallH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
        guard let small = ctx.makeImage() else { return nil }
        return NSImage(cgImage: small, size: pointSize)
    }
}

struct SelectionHandlesView: View {
    let annotation: Annotation
    let canvasOffset: CGPoint

    var body: some View {
        if annotation.kind.isLinear {
            // Two endpoint handles at the true tail/tip, in view coords.
            let tail = CGPoint(
                x: annotation.arrowTail.x + canvasOffset.x,
                y: annotation.arrowTail.y + canvasOffset.y
            )
            let tip = CGPoint(
                x: annotation.arrowTip.x + canvasOffset.x,
                y: annotation.arrowTip.y + canvasOffset.y
            )
            ZStack {
                handleDot(at: tail)
                handleDot(at: tip)
            }
        } else {
            let f = annotation.frame.standardized.offsetBy(dx: canvasOffset.x, dy: canvasOffset.y)
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: f.width + 4, height: f.height + 4)
                    .position(x: f.midX, y: f.midY)
                ForEach(Array(corners(of: f).enumerated()), id: \.offset) { _, p in
                    handleDot(at: p)
                }
            }
        }
    }

    @ViewBuilder
    private func handleDot(at p: CGPoint) -> some View {
        Circle().fill(.white)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
            .position(x: p.x, y: p.y)
    }

    private func corners(of r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
    }
}

struct CropOverlayView: View {
    let imageRect: CGRect
    let cropRect: CGRect

    var body: some View {
        Rectangle()
            .fill(.black.opacity(0.45))
            .frame(width: imageRect.width, height: imageRect.height)
            .position(x: imageRect.midX, y: imageRect.midY)
            .mask(
                ZStack {
                    Rectangle()
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)
                    Rectangle()
                        .frame(width: cropRect.width, height: cropRect.height)
                        .position(x: cropRect.midX, y: cropRect.midY)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            )
            .overlay(
                Rectangle()
                    .stroke(Color.white, lineWidth: 1.5)
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)
            )
    }
}

struct TextEditOverlay: View {
    let annotation: Annotation
    let layout: CanvasLayout
    @Binding var text: String
    let onCommit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        // .fixedSize keeps the editor exactly as wide as the typed text + a small
        // padding — no giant horizontal bar behind a single word.
        TextField("Text", text: $text)
            .focused($focused)
            .font(.system(size: annotation.fontSize, weight: .semibold))
            .foregroundStyle(annotation.color.swiftUI)
            .textFieldStyle(.plain)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.accentColor.opacity(0.7), lineWidth: 1)
                    )
            )
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: layout.canvasOrigin.x + annotation.frame.minX - 4,
                    y: layout.canvasOrigin.y + annotation.frame.minY - 2)
            .onAppear {
                // Defer the focus request to the next runloop so the TextField
                // is fully attached to its window before we ask for first-responder.
                DispatchQueue.main.async { focused = true }
            }
            .onSubmit { onCommit() }
            .onExitCommand { onCommit() }
    }
}
