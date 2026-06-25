import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
import Foundation

enum GIFEncoder {
    /// Encode timestamped (PNG) frames into animated GIF data.
    ///
    /// Per-frame delays come from the gap to the *next* frame's timestamp, so
    /// pauses during recording compress naturally (a frame that stayed on screen
    /// longer is simply held longer). Loops forever. Frames are copied straight
    /// from their PNG source into the GIF, so only one frame is in memory at once.
    static func encode(frames: [GIFRecorder.Frame]) -> Data? {
        guard let first = frames.first else { return nil }

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.gif.identifier as CFString, frames.count, nil
        ) else { return nil }

        // Loop count 0 = infinite.
        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)

        let span = max(0, frames[frames.count - 1].time - first.time)
        let averageDelay = (frames.count > 1 && span > 0) ? span / Double(frames.count - 1) : 0.1

        var added = 0
        for i in frames.indices {
            guard let src = CGImageSourceCreateWithData(frames[i].data as CFData, nil),
                  CGImageSourceGetCount(src) > 0 else { continue }
            let delay: Double = i < frames.count - 1 ? frames[i + 1].time - frames[i].time : averageDelay
            let clamped = min(10.0, max(0.02, delay))
            CGImageDestinationAddImageFromSource(dest, src, 0, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: clamped]
            ] as CFDictionary)
            added += 1
        }

        guard added > 0, CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
