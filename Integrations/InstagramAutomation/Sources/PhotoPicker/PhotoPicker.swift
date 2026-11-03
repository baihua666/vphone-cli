import Foundation
#if VPHONE_CUSTOM_PHOTO_SELECTION
import CoreGraphics
import ImageIO
import Vision
#endif

public struct PhotoPickerError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

/// UI-only operation: no application identity, credentials, import, caption or publication.
public struct PhotoPicker {
    public typealias RPC = (String, [String: Any]) throws -> [String: Any]
    let rpc: RPC
    public init(rpc: @escaping RPC) { self.rpc = rpc }
    public static var isEnabled: Bool {
        #if VPHONE_CUSTOM_PHOTO_SELECTION
        true
        #else
        false
        #endif
    }

    public func select(image: URL) throws {
        #if VPHONE_CUSTOM_PHOTO_SELECTION
        let screen = try dimensions()
        let elements = try tree()
        try Self.validateSelected(elements, screen: screen)
        let candidates = Self.cells(elements, screen: screen)
        let chosen = try match(image: image, candidates: candidates, screen: screen)
        // Re-read immediately before acting so an animation or changed selection cannot redirect input.
        let freshElements = try tree(), freshScreen = try dimensions()
        try Self.validateSelected(freshElements, screen: freshScreen)
        let fresh = Self.cells(freshElements, screen: freshScreen)
        guard fresh == candidates else { throw PhotoPickerError("照片页面已变化，请重试选图") }
        let target = candidates[chosen]
        if !target.selected {
            _ = try rpc("input.tap", ["x": Double(target.frame.midX), "y": Double(target.frame.midY)])
        }
        let deadline = Date().addingTimeInterval(5)
        repeat {
            let elements = try tree()
            try Self.validateSelected(elements, screen: screen)
            let selected = Self.cells(elements, screen: screen).filter(\.selected)
            if selected.count == 1, selected[0].frame == target.frame { return }
            if selected.count > 1 { throw PhotoPickerError("选择后出现多张选中图片，未确认完成") }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        throw PhotoPickerError("未确认照片选中状态；未点击完成")
        #else
        throw PhotoPickerError("通用照片选择未编译启用")
        #endif
    }

    /// Check a caller-supplied attachment view using the same image matching implementation.
    public func verify(image: URL, identifier: String) throws {
        #if VPHONE_CUSTOM_PHOTO_SELECTION
        try verify(image: image, frames: tree().filter { $0["identifier"] as? String == identifier })
        #else
        throw PhotoPickerError("通用照片选择未编译启用")
        #endif
    }

    public func verify(image: URL, frames: [[String: Any]]) throws {
        #if VPHONE_CUSTOM_PHOTO_SELECTION
        guard frames.count == 1 else { throw PhotoPickerError("附件数量不是一张") }
        let screen = try dimensions()
        let candidates = frames.compactMap { Self.cell($0, screen: screen) }
        guard candidates.count == 1 else { throw PhotoPickerError("附件数量不是一张") }
        _ = try match(image: image, candidates: candidates, screen: screen, inset: 0.2)
        #else
        throw PhotoPickerError("通用照片选择未编译启用")
        #endif
    }

    #if VPHONE_CUSTOM_PHOTO_SELECTION
    struct Cell: Equatable {
        let frame: CGRect
        let selected: Bool
    }
    static func validateSelected(_ elements: [[String: Any]], screen: CGSize) throws {
        for element in elements {
            let id = element["identifier"] as? String ?? ""
            guard id == "PXGGridLayout-Info" || id.hasPrefix("grid-view-cell-") else { continue }
            if ((element["traits"] as? NSNumber)?.uint64Value ?? 0) & 8 != 0,
               cell(element, screen: screen) == nil {
                throw PhotoPickerError("已有选中照片未完整显示，停止修改")
            }
        }
    }
    static func cell(_ element: [String: Any], screen: CGSize) -> Cell? {
        guard let f = element["frame"] as? [String: Double], let x = f["x"], let y = f["y"],
              let w = f["width"], let h = f["height"], [x,y,w,h].allSatisfy(\.isFinite),
              w > 30, h > 30, x >= -0.01, y >= -0.01,
              x+w <= screen.width+0.01, y+h <= screen.height+0.01 else { return nil }
        let rect = CGRect(x: x, y: y, width: w, height: h).intersection(CGRect(origin: .zero, size: screen))
        return Cell(frame: rect, selected: ((element["traits"] as? NSNumber)?.uint64Value ?? 0) & 8 != 0)
    }
    static func cells(_ elements: [[String: Any]], screen: CGSize) -> [Cell] {
        elements.compactMap { element in
            let id = element["identifier"] as? String ?? ""
            guard id == "PXGGridLayout-Info" || id.hasPrefix("grid-view-cell-") else { return nil }
            return cell(element, screen: screen)
        }.sorted { $0.frame.minY == $1.frame.minY ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY }
    }
    static func choose(distances: [Float], selected: [Bool], equivalent: (Int, Int) throws -> Bool) throws -> Int {
        guard !distances.isEmpty else { throw PhotoPickerError("未找到可见照片格子，照片选择器尚未就绪或不受支持") }
        guard distances.count == selected.count, distances.allSatisfy(\.isFinite) else { throw PhotoPickerError("图片匹配数据无效") }
        let ranked = distances.indices.sorted { distances[$0] < distances[$1] }
        let best = ranked[0]
        guard distances[best] < 0.25 else { throw PhotoPickerError("可见照片中未匹配到原图（距离：\(distances)）") }
        let close = ranked.filter { distances[$0] - distances[best] <= 0.10 }
        for other in close where other != best {
            guard distances[other] < 0.25, try equivalent(best, other) else {
                throw PhotoPickerError("存在相似但不等价的图片，停止选图")
            }
        }
        let existing = selected.indices.filter { selected[$0] }
        guard existing.count <= 1, existing.allSatisfy(close.contains) else {
            throw PhotoPickerError("选择器已有其它或多张选中图片，停止修改")
        }
        return existing.first ?? close.min()!
    }
    func tree() throws -> [[String: Any]] {
        let result = try rpc("ui.tree", ["max_elements": 300])
        guard result["truncated"] as? Bool != true, let elements = result["elements"] as? [[String: Any]] else {
            throw PhotoPickerError("无法读取照片选择器")
        }
        return elements
    }
    func dimensions() throws -> CGSize {
        let state = try rpc("device.screen", [:])
        guard let w = state["width"] as? Double, let h = state["height"] as? Double,
              w.isFinite, h.isFinite, w > 0, h > 0 else { throw PhotoPickerError("无法读取实时屏幕尺寸") }
        return CGSize(width: w, height: h)
    }
    static func feature(_ image: CGImage) throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        request.imageCropAndScaleOption = .centerCrop
        try VNImageRequestHandler(cgImage: image).perform([request])
        guard let observation = request.results?.first else { throw PhotoPickerError("无法读取图片特征") }
        return observation
    }
    static func aspectFillRect(source: CGSize, target: CGSize) -> CGRect {
        let scale = max(target.width/source.width, target.height/source.height)
        let width = target.width/scale, height = target.height/scale
        return CGRect(x: (source.width-width)/2, y: (source.height-height)/2, width: width, height: height)
    }
    static func pixels(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 32*32*4)
        let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 32, height: 32, bitsPerComponent: 8,
                bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            return true
        }
        guard ok else { throw PhotoPickerError("无法比较重复图片") }
        return bytes
    }
    static func pixelError(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var total = 0.0
        for index in a.indices where index % 4 != 3 {
            total += abs(Double(a[index]) - Double(b[index]))
        }
        return total / Double(32*32*3*255)
    }
    static func matchDistance(feature: Float, pixelError: Double) -> Float {
        // Thumbnail resampling can perturb Vision features. Only a second, strict aligned
        // RGB comparison can corroborate it; never widen the feature-only threshold.
        feature.isFinite && feature < 0.75 && pixelError < 0.018 ? min(feature, Float(pixelError)) : feature
    }
    func match(image: URL, candidates: [Cell], screen: CGSize, inset: Double = 0) throws -> Int {
        guard !candidates.isEmpty else { throw PhotoPickerError("未找到可见照片格子，照片选择器尚未就绪或不受支持") }
        guard let source = CGImageSourceCreateWithURL(image as CFURL, nil),
              let original = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2048] as CFDictionary),
              let encoded = try rpc("screen.screenshot", [:])["data"] as? String,
              let data = Data(base64Encoded: encoded), let captureSource = CGImageSourceCreateWithData(data as CFData, nil),
              let capture = CGImageSourceCreateImageAtIndex(captureSource, 0, nil) else { throw PhotoPickerError("无法读取原图或截图") }
        var distances: [Float] = [], pixelErrors: [Double] = [], crops: [[UInt8]] = []
        for cell in candidates {
            let f = cell.frame
            let rect = CGRect(x: f.minX * Double(capture.width)/screen.width, y: f.minY * Double(capture.height)/screen.height,
                width: f.width * Double(capture.width)/screen.width, height: f.height * Double(capture.height)/screen.height)
            let contentRect = rect.insetBy(dx: rect.width*inset, dy: rect.height*inset)
            guard let crop = capture.cropping(to: contentRect) else { throw PhotoPickerError("照片格子超出截图范围") }
            let referenceRect = Self.aspectFillRect(source: CGSize(width: original.width, height: original.height), target: f.size)
            let referenceContent = referenceRect.insetBy(dx: referenceRect.width*inset, dy: referenceRect.height*inset)
            guard let referenceImage = original.cropping(to: referenceContent) else { throw PhotoPickerError("无法裁剪原图参考") }
            let reference = try Self.feature(referenceImage)
            var distance: Float = 0
            try reference.computeDistance(&distance, to: Self.feature(crop))
            let pixels = try Self.pixels(crop)
            let error = Self.pixelError(pixels, try Self.pixels(referenceImage))
            pixelErrors.append(error)
            distances.append(Self.matchDistance(feature: distance, pixelError: error))
            crops.append(pixels)
        }
        if distances.allSatisfy({ $0 >= 0.25 }) {
            throw PhotoPickerError("可见图片未匹配原图：特征/组合距离 \(distances)，像素误差 \(pixelErrors)")
        }
        return try Self.choose(distances: distances, selected: candidates.map(\.selected)) { a,b in
            Self.pixelError(crops[a], crops[b]) < 0.018
        }
    }
    #endif
}
