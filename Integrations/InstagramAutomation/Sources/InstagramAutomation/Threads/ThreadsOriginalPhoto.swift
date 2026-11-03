import Foundation
import ImageIO
import CoreGraphics
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION && VPHONE_CUSTOM_THREADS_AUTOMATION
/// Match local image content against visible photo cells; never modify the upload.
struct ThreadsOriginalPhoto {
    let ui: Screen
    let source: URL

    // Compare normalized pixels instead of semantic similarity: thumbnails of the
    // same artwork must match even when the picker adds a small selection badge.
    static func pixels(_ image: CGImage) throws -> [UInt8] {
        let side = min(image.width, image.height)
        guard let square = image.cropping(to: CGRect(x: (image.width - side) / 2,
            y: (image.height - side) / 2, width: side, height: side)) else { throw Failure("无法裁取图片内容") }
        var bytes = [UInt8](repeating: 0, count: 32 * 32 * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 32, height: 32,
                bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure("无法比较图片内容") }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            context.draw(square, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        return bytes
    }

    static func distance(_ lhs: [UInt8], _ rhs: [UInt8]) -> Float {
        guard lhs.count == 4096, rhs.count == lhs.count else { return .infinity }
        var difference: Float = 0
        for index in lhs.indices where index % 4 != 3 {
            difference += abs(Float(lhs[index]) - Float(rhs[index])) / 255
        }
        return difference / (32 * 32 * 3)
    }

    static func uniqueIndex(distances: [Float]) throws -> Int {
        let ranked = distances.enumerated().sorted { $0.element < $1.element }
        guard let best = ranked.first, best.element.isFinite, best.element < 0.08,
              ranked.count == 1 || ranked[1].element - best.element > 0.10 else {
            throw Failure("无法唯一识别原图，未选择照片；请检查相册或草稿")
        }
        return best.offset
    }

    static func cropRect(frame: [String: Double], width: Int, height: Int) -> CGRect? {
        guard let x = frame["x"], let y = frame["y"], let w = frame["width"], let h = frame["height"],
              [x, y, w, h].allSatisfy(\.isFinite), w > 30, h > 30,
              x >= -0.01, y >= -0.01, x + w <= 430.01, y + h <= 932.01 else { return nil }
        // AX reports the left edge as -0.000003 on the system photo picker.
        // Clamp numerical rounding only; genuinely off-screen cells remain excluded.
        return CGRect(x: max(0, x) * Double(width) / 430, y: max(0, y) * Double(height) / 932,
                      width: (min(430, x + w) - max(0, x)) * Double(width) / 430,
                      height: (min(932, y + h) - max(0, y)) * Double(height) / 932)
    }

    func matchingCell(_ cells: [[String: Any]]) throws -> [String: Any] {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let original = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              let captureSource = CGImageSourceCreateWithData(try ui.image() as CFData, nil),
              let capture = CGImageSourceCreateImageAtIndex(captureSource, 0, nil) else {
            throw Failure("无法读取原图或截图")
        }
        let reference = try Self.pixels(original)
        var candidates: [[String: Any]] = []
        var distances: [Float] = []
        for cell in cells {
            guard let frame = cell["frame"] as? [String: Double],
                  let rect = Self.cropRect(frame: frame, width: capture.width, height: capture.height),
                  let cropped = capture.cropping(to: rect) else { continue }
            let distance = Self.distance(reference, try Self.pixels(cropped))
            candidates.append(cell); distances.append(distance)
        }
        print("photo-match: " + distances.map { String(format: "%.3f", $0) }.joined(separator: ", ")); fflush(stdout)
        return candidates[try Self.uniqueIndex(distances: distances)]
    }

    func select(permission: Bool) throws {
        let cells = try ui.tree().filter {
            let id = $0["identifier"] as? String ?? ""
            return permission ? id == "PXGGridLayout-Info" : id.hasPrefix("grid-view-cell-")
        }
        print(permission ? "photo: permission picker" : "photo: Threads picker"); fflush(stdout)
        let cell = try matchingCell(cells)
        if (cell["traits"] as? UInt64 ?? 0) & 8 != 0 { return }
        guard let frame = cell["frame"] as? [String: Double], let x = frame["x"], let y = frame["y"],
              let width = frame["width"], let height = frame["height"] else { throw Failure("图片格子位置不可用") }
        try ui.point(x + width / 2, y + height / 2)
    }

    func checkAttachment() throws {
        let cells = try ui.tree().filter { $0["identifier"] as? String == "image-view" }
        _ = try matchingCell(cells)
    }
}
#endif
