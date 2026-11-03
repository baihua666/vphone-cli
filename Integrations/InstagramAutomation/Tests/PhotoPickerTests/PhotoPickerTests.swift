import XCTest
import CoreGraphics
import ImageIO
@testable import PhotoPicker

#if VPHONE_CUSTOM_PHOTO_SELECTION
final class PhotoPickerTests: XCTestCase {
    func testRealImageMatchingTransportScalesAndConfirmsOnlyOneDuplicate() throws {
        func context(_ w: Int, _ h: Int) -> CGContext {
            CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        }
        func png(_ image: CGImage) -> Data {
            let data = NSMutableData()
            let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            return data as Data
        }
        let source = context(128, 192)
        for y in stride(from: 0, to: 192, by: 8) {
            for x in stride(from: 0, to: 128, by: 8) {
                source.setFillColor(CGColor(red: CGFloat((x+y)%128)/128, green: CGFloat((x*3+y)%192)/192, blue: CGFloat((y*5+x)%128)/128, alpha: 1))
                source.fill(CGRect(x: x, y: y, width: 8, height: 8))
            }
        }
        let original = source.makeImage()!
        let reference = original.cropping(to: CGRect(x: 0, y: 32, width: 128, height: 128))!
        let capture = context(480, 600)
        capture.draw(reference, in: CGRect(x: 0, y: 160, width: 200, height: 200))
        capture.draw(reference, in: CGRect(x: 220, y: 160, width: 200, height: 200))
        let encoded = png(capture.makeImage()!).base64EncodedString()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try png(original).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var taps: [[String: Any]] = []
        let picker = PhotoPicker { method, params in
            switch method {
            case "device.screen": return ["width": 240.0, "height": 300.0]
            case "ui.tree": return ["elements": [self.cell("PXGGridLayout-Info", selected: !taps.isEmpty), self.cell("PXGGridLayout-Info", x: 110)]]
            case "screen.screenshot": return ["data": encoded]
            case "input.tap": taps.append(params); return [:]
            default: XCTFail("Unexpected operation: \(method)"); return [:]
            }
        }
        try picker.select(image: url)
        XCTAssertEqual(taps.count, 1)
        XCTAssertEqual(taps[0]["x"] as? Double, 50)
        XCTAssertEqual(taps[0]["y"] as? Double, 170)
    }
    func cell(_ id: String, x: Double = 0, selected: Bool = false) -> [String: Any] {
        ["identifier": id, "frame": ["x": x, "y": 120.0, "width": 100.0, "height": 100.0], "traits": selected ? UInt64(8) : UInt64(0)]
    }
    func testCurrentAndLegacyPickerAndFloatingBoundary() throws {
        let cells = PhotoPicker.cells([cell("PXGGridLayout-Info", x: -0.0000034), cell("grid-view-cell-1", x: 110), cell("other", x: 220)], screen: CGSize(width: 430, height: 932))
        XCTAssertEqual(cells.count, 2)
        XCTAssertEqual(cells[0].frame.minX, 0)
        XCTAssertEqual(PhotoPicker.cells([cell("PXGGridLayout-Info", x: -10)], screen: CGSize(width: 430, height: 932)).count, 0)
    }
    func testOffscreenSelectedCellMustNotDisappearFromSelectionGuard() {
        XCTAssertThrowsError(try PhotoPicker.validateSelected([cell("PXGGridLayout-Info", x: -10, selected: true)], screen: CGSize(width: 430, height: 932)))
    }
    func testVerifyCountsRawAttachmentsBeforeFilteringFrames() {
        let picker = PhotoPicker { _,_ in XCTFail("Multiple attachments must fail before reading screenshot or dimensions"); return [:] }
        XCTAssertThrowsError(try picker.verify(image: URL(fileURLWithPath: "/absent"), frames: [cell("image-view"), cell("image-view", x: -10)]))
    }
    func testDuplicateEquivalenceSelectsStableOneAndPrefersSelected() throws {
        XCTAssertEqual(try PhotoPicker.choose(distances: [0.06, 0.05], selected: [false, false], equivalent: { _,_ in true }), 0)
        XCTAssertEqual(try PhotoPicker.choose(distances: [0.06, 0.05], selected: [false, true], equivalent: { _,_ in true }), 1)
        XCTAssertThrowsError(try PhotoPicker.choose(distances: [0.06, 0.05], selected: [true, true], equivalent: { _,_ in true }))
    }
    func testSimilarButDifferentImagesRefuseAndNoMatchIsDistinct() {
        XCTAssertThrowsError(try PhotoPicker.choose(distances: [0.06, 0.05], selected: [false, false], equivalent: { _,_ in false }))
        XCTAssertThrowsError(try PhotoPicker.choose(distances: [], selected: [], equivalent: { _,_ in true }))
        XCTAssertThrowsError(try PhotoPicker.choose(distances: [0.8], selected: [false], equivalent: { _,_ in true }))
        XCTAssertThrowsError(try PhotoPicker.choose(distances: [.nan], selected: [false], equivalent: { _,_ in true }))
    }
    func testUniqueMatchAndUnrelatedSelection() throws {
        XCTAssertEqual(try PhotoPicker.choose(distances: [0.7, 0.05], selected: [false, false], equivalent: { _,_ in false }), 1)
        XCTAssertThrowsError(try PhotoPicker.choose(distances: [0.7, 0.05], selected: [true, false], equivalent: { _,_ in true }))
    }
    func testAspectFillUsesVisibleCenterInsteadOfWholePortrait() {
        XCTAssertEqual(PhotoPicker.aspectFillRect(source: CGSize(width: 900, height: 1400), target: CGSize(width: 100, height: 100)), CGRect(x: 0, y: 250, width: 900, height: 900))
        XCTAssertEqual(PhotoPicker.aspectFillRect(source: CGSize(width: 1400, height: 900), target: CGSize(width: 100, height: 100)), CGRect(x: 250, y: 0, width: 900, height: 900))
    }
    func testThumbnailResamplingNeedsStrictPixelEvidenceNotLooserFeatureThreshold() {
        XCTAssertLessThan(PhotoPicker.matchDistance(feature: 0.39, pixelError: 0.011), 0.25)
        XCTAssertLessThan(PhotoPicker.matchDistance(feature: 0.64, pixelError: 0.0123), 0.25)
        XCTAssertGreaterThan(PhotoPicker.matchDistance(feature: 0.39, pixelError: 0.08), 0.25)
        XCTAssertGreaterThan(PhotoPicker.matchDistance(feature: 0.8, pixelError: 0.011), 0.25)
    }
}
#else
final class DisabledPhotoPickerTests: XCTestCase {
    func testDisabledNeverCallsTransport() {
        let picker = PhotoPicker { _,_ in XCTFail("Disabled module called transport"); return [:] }
        XCTAssertThrowsError(try picker.select(image: URL(fileURLWithPath: "/absent.png")))
    }
}
#endif
