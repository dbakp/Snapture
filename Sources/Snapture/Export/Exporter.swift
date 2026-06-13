import AppKit

enum Exporter {
    @discardableResult
    static func copyToClipboard(_ image: NSImage) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return pb.writeObjects([image])
        }
        // Provide both PNG (for paste in image-aware apps) and the NSImage object.
        pb.setData(png, forType: .png)
        pb.setData(tiff, forType: .tiff)
        return true
    }

    static func write(_ image: NSImage, to url: URL) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: url)
            return true
        } catch {
            NSLog("Snapture save failed: \(error)")
            return false
        }
    }
}
