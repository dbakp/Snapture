import SwiftUI
import CoreGraphics
import AppKit

/// A drawable, editable element placed on top of the screenshot composition.
struct Annotation: Identifiable, Equatable {
    let id: UUID
    var kind: Kind
    var frame: CGRect     // canvas-space, origin top-left
    var color: CodableColor
    var fillColor: CodableColor
    var fillOpacity: Double
    var strokeWidth: CGFloat
    var text: String
    var fontSize: CGFloat
    var blurRadius: CGFloat
    var cornerRadius: CGFloat

    // Per-layer shadow
    var shadowEnabled: Bool
    var shadowRadius: CGFloat
    var shadowOpacity: Double

    // For .image: a reference to the bitmap that lives in this layer.
    var image: ImageRef?

    // For .magnifier: zoom factor (1×–10×).
    var zoom: CGFloat

    // For .pen: stroke points normalized to the frame (0…1 on both axes),
    // so moving/resizing the frame moves/scales the stroke for free.
    var points: [CGPoint]

    // For .counter: the number shown in the badge.
    var counterValue: Int

    // For .blur: mosaic pixelation instead of gaussian blur.
    var pixelate: Bool

    enum Kind: String, CaseIterable, Identifiable {
        case rectangle, ellipse, triangle, line, arrow, pen, text, counter, blur, highlight, image, magnifier
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .rectangle: return "Rectangle"
            case .ellipse:   return "Ellipse"
            case .triangle:  return "Triangle"
            case .line:      return "Line"
            case .arrow:     return "Arrow"
            case .pen:       return "Pen"
            case .text:      return "Text"
            case .counter:   return "Step badge"
            case .blur:      return "Blur"
            case .highlight: return "Highlight"
            case .image:     return "Image"
            case .magnifier: return "Magnifier"
            }
        }

        var systemImage: String {
            switch self {
            case .rectangle: return "rectangle"
            case .ellipse:   return "circle"
            case .triangle:  return "triangle"
            case .line:      return "line.diagonal"
            case .arrow:     return "arrow.up.right"
            case .pen:       return "scribble"
            case .text:      return "textformat"
            case .counter:   return "1.circle"
            case .blur:      return "drop.halffull"
            case .highlight: return "rectangle.dashed"
            case .image:     return "photo"
            case .magnifier: return "plus.magnifyingglass"
            }
        }

        /// Does a drop-shadow setting make sense on this kind?
        var supportsShadow: Bool {
            switch self {
            case .rectangle, .ellipse, .triangle, .image, .text, .magnifier, .counter: return true
            case .line, .arrow, .pen, .blur, .highlight: return false
            }
        }

        /// Is this a closed shape with stroke/fill controls?
        var isShape: Bool {
            switch self {
            case .rectangle, .ellipse, .triangle: return true
            default: return false
            }
        }

        /// Tail→tip vector annotations: stored with possibly-negative frame
        /// sizes encoding direction, edited via endpoint handles.
        var isLinear: Bool {
            self == .arrow || self == .line
        }
    }

    static func make(kind: Kind, frame: CGRect, defaults: AnnotationDefaults, image: ImageRef? = nil) -> Annotation {
        let initialFillOpacity: Double = (kind == .highlight) ? 0.7 : defaults.fillOpacity
        let initialCornerRadius: CGFloat = (kind == .highlight) ? 8 : (kind == .image ? 10 : defaults.cornerRadius)
        // New text annotations start empty so the placeholder "Text" shows
        // and the first keystroke types real content.
        let initialText: String = ""
        return Annotation(
            id: UUID(),
            kind: kind,
            frame: frame,
            color: defaults.color,
            fillColor: defaults.fillColor,
            fillOpacity: initialFillOpacity,
            strokeWidth: defaults.strokeWidth,
            text: initialText,
            fontSize: defaults.fontSize,
            blurRadius: defaults.blurRadius,
            cornerRadius: initialCornerRadius,
            shadowEnabled: defaults.shadowEnabledForLayer(kind: kind),
            shadowRadius: defaults.shadowRadius,
            shadowOpacity: defaults.shadowOpacity,
            image: image,
            zoom: defaults.magnifierZoom,
            points: [],
            counterValue: 1,
            pixelate: false
        )
    }
}

struct AnnotationDefaults: Equatable {
    var color: CodableColor = CodableColor(.red)
    var fillColor: CodableColor = CodableColor(.yellow)
    var fillOpacity: Double = 0.0
    var strokeWidth: CGFloat = 3
    var fontSize: CGFloat = 22
    var blurRadius: CGFloat = 16
    var cornerRadius: CGFloat = 4
    var shadowRadius: CGFloat = 16
    var shadowOpacity: Double = 0.35
    var magnifierZoom: CGFloat = 2.5

    func shadowEnabledForLayer(kind: Annotation.Kind) -> Bool {
        // Default ON for images, magnifiers, and step badges (visual depth),
        // OFF for shapes/text (user can opt in).
        switch kind {
        case .image, .magnifier, .counter: return true
        default: return false
        }
    }
}

extension Annotation {
    /// Arrows store tail = frame.origin and tip = origin + raw size, so the
    /// size may be NEGATIVE to encode direction.
    ///
    /// ⚠️ Never compute these with `frame.width` / `frame.height` — those CGRect
    /// accessors return ABSOLUTE values and silently mirror the tip. Only
    /// `frame.size.width` / `frame.size.height` keep the sign.
    var arrowTail: CGPoint { frame.origin }
    var arrowTip: CGPoint {
        CGPoint(x: frame.origin.x + frame.size.width,
                y: frame.origin.y + frame.size.height)
    }
}

extension CGRect {
    /// Translate preserving the raw (possibly negative) size.
    /// `offsetBy` standardizes the rect — it would flip an arrow's direction.
    func movedBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        CGRect(origin: CGPoint(x: origin.x + dx, y: origin.y + dy), size: size)
    }
}

/// Wraps an NSImage so an Annotation can stay Equatable (identity-based).
struct ImageRef: Equatable, Hashable {
    let id: UUID
    let image: NSImage
    init(_ image: NSImage) {
        self.id = UUID()
        self.image = image
    }
    static func == (l: ImageRef, r: ImageRef) -> Bool { l.id == r.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A Color that survives Equatable comparisons and serialization.
struct CodableColor: Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .red
        self.init(red: Double(ns.redComponent),
                  green: Double(ns.greenComponent),
                  blue: Double(ns.blueComponent),
                  alpha: Double(ns.alphaComponent))
    }

    var swiftUI: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}
