import Foundation
import ImageIO
import Vision
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION && VPHONE_CUSTOM_THREADS_AUTOMATION
/// Match local image content against visible photo cells; never modify the upload.
struct ThreadsOriginalPhoto {
    let ui: Screen
    let source: URL

    static func feature(_ image: CGImage) throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        request.imageCropAndScaleOption = .centerCrop
        try VNImageRequestHandler(cgImage: image).perform([request])
        guard let result = request.results?.first else { throw Failure("无法读取图片特征") }
        return result
    }

    static func uniqueIndex(distances: [Float]) throws -> Int {
        let ranked = distances.enumerated().sorted { $0.element < $1.element }
        guard let best = ranked.first, best.element.isFinite, best.element < 0.25,
              ranked.count == 1 || ranked[1].element - best.element > 0.10 else {
            throw Failure("无法唯一识别原图，未选择照片；请检查相册或草稿")
        }
        return best.offset
    }

    func matchingCell(_ cells: [[String: Any]]) throws -> [String: Any] {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let original = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              let captureSource = CGImageSourceCreateWithData(try ui.image() as CFData, nil),
              let capture = CGImageSourceCreateImageAtIndex(captureSource, 0, nil) else {
            throw Failure("无法读取原图或截图")
        }
        let reference = try Self.feature(original)
        let sx = Double(capture.width) / 430, sy = Double(capture.height) / 932
        var candidates: [[String: Any]] = []
        var distances: [Float] = []
        for cell in cells {
            guard let frame = cell["frame"] as? [String: Double],
                  let x = frame["x"], let y = frame["y"], let width = frame["width"], let height = frame["height"],
                  width > 30, height > 30, x >= 0, y >= 0, x + width <= 431, y + height <= 933,
                  let cropped = capture.cropping(to: CGRect(x: x * sx, y: y * sy, width: width * sx, height: height * sy)) else { continue }
            var distance: Float = 0
            try reference.computeDistance(&distance, to: Self.feature(cropped))
            candidates.append(cell); distances.append(distance)
        }
        return candidates[try Self.uniqueIndex(distances: distances)]
    }

    func select(permission: Bool) throws {
        let cells = try ui.tree().filter {
            let id = $0["identifier"] as? String ?? ""
            return permission ? id == "PXGGridLayout-Info" : id.hasPrefix("grid-view-cell-")
        }
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
