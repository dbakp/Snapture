import SwiftUI

enum BackgroundStyle: Equatable, Hashable {
    case transparent
    case solid(CodableColor)
    case gradient(CodableColor, CodableColor, Double)   // start, end, angle (degrees)

    @ViewBuilder
    func view() -> some View {
        switch self {
        case .transparent:
            CheckerboardPattern()
        case .solid(let c):
            c.swiftUI
        case .gradient(let a, let b, let angle):
            LinearGradient(
                colors: [a.swiftUI, b.swiftUI],
                startPoint: unitPoint(forAngle: angle, start: true),
                endPoint:   unitPoint(forAngle: angle, start: false)
            )
        }
    }

    private func unitPoint(forAngle deg: Double, start: Bool) -> UnitPoint {
        let r = deg * .pi / 180
        let dx = cos(r) * 0.5, dy = sin(r) * 0.5
        return start
            ? UnitPoint(x: 0.5 - dx, y: 0.5 - dy)
            : UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
    }
}

struct BackgroundPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let style: BackgroundStyle
}

enum BackgroundPresets {
    static let all: [BackgroundPreset] = [
        .init(id: "none", name: "None",
              style: .transparent),
        .init(id: "white", name: "White",
              style: .solid(CodableColor(.white))),
        .init(id: "black", name: "Black",
              style: .solid(CodableColor(.black))),
        .init(id: "indigo", name: "Indigo",
              style: .gradient(CodableColor(red: 0.32, green: 0.27, blue: 0.91),
                               CodableColor(red: 0.55, green: 0.36, blue: 0.96), 45)),
        .init(id: "sunset", name: "Sunset",
              style: .gradient(CodableColor(red: 0.99, green: 0.55, blue: 0.32),
                               CodableColor(red: 0.96, green: 0.27, blue: 0.45), 30)),
        .init(id: "ocean", name: "Ocean",
              style: .gradient(CodableColor(red: 0.14, green: 0.51, blue: 0.93),
                               CodableColor(red: 0.31, green: 0.78, blue: 0.94), 60)),
        .init(id: "lime", name: "Lime",
              style: .gradient(CodableColor(red: 0.51, green: 0.84, blue: 0.31),
                               CodableColor(red: 0.13, green: 0.71, blue: 0.51), 50)),
        .init(id: "graphite", name: "Graphite",
              style: .gradient(CodableColor(red: 0.18, green: 0.18, blue: 0.21),
                               CodableColor(red: 0.32, green: 0.32, blue: 0.36), 90)),
        .init(id: "rose", name: "Rose",
              style: .gradient(CodableColor(red: 0.96, green: 0.55, blue: 0.73),
                               CodableColor(red: 0.95, green: 0.31, blue: 0.52), 30)),
    ]
}

struct CheckerboardPattern: View {
    /// One 2×2-cell tile rendered once; the GPU repeats it. The previous
    /// Canvas version issued ~16k fill calls per render of a large canvas.
    @MainActor private static let tile: NSImage = {
        let cell: CGFloat = 12
        let size = NSSize(width: cell * 2, height: cell * 2)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.gray.withAlphaComponent(0.15).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.gray.withAlphaComponent(0.30).setFill()
        NSRect(x: 0, y: 0, width: cell, height: cell).fill()
        NSRect(x: cell, y: cell, width: cell, height: cell).fill()
        image.unlockFocus()
        return image
    }()

    var body: some View {
        Image(nsImage: Self.tile)
            .resizable(resizingMode: .tile)
    }
}
