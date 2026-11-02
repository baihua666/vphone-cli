#if VPHONE_CUSTOM_THREADS_DESKTOP
import AppKit
import CoreImage

public enum ThreadsImage {
    /// Preserve the selected image, fitting it above a visible task-identification strip.
    public static func prepare(source: URL, marker: String, destination: URL) throws {
        guard let original = NSImage(contentsOf: source), original.size.width > 0, original.size.height > 0,
              let filter = CIFilter(name: "CIQRCodeGenerator") else { throw ThreadsDesktopError("无法读取所选图片") }
        filter.setValue(Data(marker.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage,
              let qr = CIContext().createCGImage(output, from: output.extent) else { throw ThreadsDesktopError("无法生成图片识别码") }
        let image = NSImage(size: NSSize(width: 1080, height: 1080))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1080, height: 1080).fill()
        let scale = min(1080 / original.size.width, 670 / original.size.height)
        let width = original.size.width * scale, height = original.size.height * scale
        original.draw(in: NSRect(x: (1080 - width) / 2, y: 410 + (670 - height) / 2, width: width, height: height))
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: qr, size: .zero).draw(in: NSRect(x: 30, y: 30, width: 340, height: 340))
        for (text, y, size) in [(marker, 215.0, 65.0), ("Threads automation", 130.0, 42.0)] {
            (text as NSString).draw(at: NSPoint(x: 390, y: y), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: size, weight: .bold), .foregroundColor: NSColor.black])
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { throw ThreadsDesktopError("无法保存发布图片") }
        try png.write(to: destination, options: .atomic)
    }
}

#endif
