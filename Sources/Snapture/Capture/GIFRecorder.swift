import ScreenCaptureKit
import CoreImage
import CoreMedia
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import AppKit

/// Records a region of a display with ScreenCaptureKit and collects frames for
/// GIF encoding.
///
/// Frames are stored **PNG-compressed** (≈25× smaller than raw), so a recording
/// isn't bounded by a short memory limit — there's only a very high safety cap
/// to avoid an unbounded runaway. Frames arrive on a background queue; start/stop
/// are async and meant to be awaited from the main actor.
final class GIFRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {

    /// A captured frame: PNG-encoded image data plus its presentation time (s).
    struct Frame: @unchecked Sendable {
        let data: Data
        let time: Double
    }

    private let sync = DispatchQueue(label: "com.snapture.gif.frames")
    private let sampleQueue = DispatchQueue(label: "com.snapture.gif.samples", qos: .userInitiated)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private var stream: SCStream?
    private var frames: [Frame] = []     // guarded by `sync`
    private var totalBytes = 0           // guarded by `sync`
    private var reachedCap = false       // guarded by `sync`

    /// ~2 GB of compressed frames — many minutes even at high quality. Effectively
    /// "no limit" for real GIFs; only a backstop against an accidental runaway.
    private let byteBudget = 2_000_000_000

    /// Called once (main queue) if the safety cap is hit, so the owner can stop.
    var onReachCap: (() -> Void)?

    @MainActor
    func start(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws {
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    @MainActor
    func stop() async -> [Frame] {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        return sync.sync { frames }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        if sync.sync(execute: { reachedCap }) { return }

        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }

        let time = sampleBuffer.presentationTimeStamp.seconds
        guard time.isFinite else { return }

        // Render + PNG-compress on the sample queue. If this can't keep up,
        // ScreenCaptureKit simply drops frames (a lower effective fps) — fine
        // for a GIF, and it keeps memory bounded to the compressed frames.
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard ciImage.extent.width > 0, ciImage.extent.height > 0,
              let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent),
              let png = Self.pngData(cgImage) else { return }

        sync.sync {
            guard !reachedCap else { return }
            frames.append(Frame(data: png, time: time))
            totalBytes += png.count
            if totalBytes >= byteBudget {
                reachedCap = true
                DispatchQueue.main.async { [weak self] in self?.onReachCap?() }
            }
        }
    }

    private static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("Snapture: GIF stream stopped: \(error.localizedDescription)")
    }
}
