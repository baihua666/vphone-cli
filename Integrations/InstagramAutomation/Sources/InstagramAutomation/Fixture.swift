import AppKit
import CoreImage
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION
enum Fixture {
    static func create(marker: String, at url: URL, title: String = "Instagram automation", markerSize: Double = 44, barcode: Bool = false) throws {
        var qr: CGImage?
        if barcode {
            guard let filter = CIFilter(name: "CIQRCodeGenerator") else { throw Failure("二维码生成不可用") }
            filter.setValue(Data(marker.utf8), forKey: "inputMessage")
            filter.setValue("M", forKey: "inputCorrectionLevel")
            guard let output = filter.outputImage,
                  let code = CIContext().createCGImage(output, from: output.extent) else { throw Failure("二维码生成失败") }
            qr = code
        }
        let image = NSImage(size: NSSize(width: 1080, height: 1080))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1080, height: 1080).fill()
        NSColor.systemTeal.setFill()
        NSRect(x: 60, y: 60, width: 960, height: 160).fill()
        let heading = barcode ? "" : "VPHONE TEST"
        for (text, y, size) in [(heading, 680.0, 90.0), (marker, 490.0, markerSize), (title, 350.0, 48.0)] {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: size, weight: .bold),
                                                            .foregroundColor: NSColor.black]
            let width = (text as NSString).size(withAttributes: attributes).width
            (text as NSString).draw(at: NSPoint(x: (1080 - width) / 2, y: y), withAttributes: attributes)
        }
        if let qr {
            NSGraphicsContext.current?.imageInterpolation = .none
            NSImage(cgImage: qr, size: .zero).draw(in: NSRect(x: 360, y: 700, width: 360, height: 360))
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else { throw Failure("无法生成测试图") }
        try data.write(to: url, options: .atomic)
    }
}
#endif
