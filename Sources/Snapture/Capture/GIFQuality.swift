import CoreGraphics
import Foundation

/// Maps a 0…1 "quality" value to GIF capture parameters (output resolution + fps)
/// and provides a rough size estimate so the recorder can show the trade-off.
enum GIFQuality {
    /// Output never exceeds this on its longest edge — high enough that typical
    /// regions are captured at native Retina (sharp), with a sane ceiling.
    static let longestEdgeCap: CGFloat = 2560

    // GIF/LZW compresses screen content enormously and ScreenCaptureKit drops
    // unchanged frames, so real size depends mostly on how much MOVES. These
    // per-pixel-per-frame coefficients bracket "barely moving" → "very busy".
    private static let lowBytesPerPixelPerFrame: Double = 0.003
    private static let highBytesPerPixelPerFrame: Double = 0.06

    static func clampedQuality(_ q: Double) -> Double { min(max(q, 0), 1) }

    /// Output points-per-point scale: 0.5× (small) up to native Retina (≤2×).
    static func outputScale(_ quality: Double, retinaScale: CGFloat) -> CGFloat {
        let maxScale = min(max(retinaScale, 1), 2)
        return 0.5 + CGFloat(clampedQuality(quality)) * (maxScale - 0.5)
    }

    static func fps(_ quality: Double) -> Int {
        Int((8 + clampedQuality(quality) * 7).rounded())   // 8…15
    }

    /// Output frame size in pixels for a region measured in points.
    static func pixelSize(regionPoints: CGSize, quality: Double, retinaScale: CGFloat) -> CGSize {
        let s = outputScale(quality, retinaScale: retinaScale)
        var w = regionPoints.width * s
        var h = regionPoints.height * s
        let longest = max(w, h)
        if longest > longestEdgeCap {
            let k = longestEdgeCap / longest
            w *= k; h *= k
        }
        return CGSize(width: max(2, w.rounded()), height: max(2, h.rounded()))
    }

    /// Rough (low, high) bytes/second bracket for the chosen settings + region.
    static func estimatedRange(regionPoints: CGSize, quality: Double, retinaScale: CGFloat) -> (low: Double, high: Double) {
        let px = pixelSize(regionPoints: regionPoints, quality: quality, retinaScale: retinaScale)
        let perFrame = Double(px.width * px.height) * Double(fps(quality))
        return (perFrame * lowBytesPerPixelPerFrame, perFrame * highBytesPerPixelPerFrame)
    }
}
