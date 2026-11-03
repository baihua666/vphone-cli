import XCTest
import AppKit
import Vision
import ThreadsDesktop
@testable import InstagramAutomation
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION && VPHONE_CUSTOM_THREADS_AUTOMATION
final class ThreadsTests: XCTestCase {
    func testVerificationPausesWithoutChangingLoginOrPublicationCheckpoint() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let journal = try RunJournal(directory: root, socket: root.appendingPathComponent("vphone.sock").path,
                                     account: "test409518", freshLogin: false, platform: "threads")
        XCTAssertFalse(journal.state.loginSubmitted)
        for label in ["Enter the code", "Security code", "请输入验证码", "双重验证"] {
            XCTAssertThrowsError(try ThreadsSession.checkVerification([["label": label]], journal: journal)) {
                XCTAssertTrue($0 is VerificationRequired)
            }
        }
        XCTAssertTrue(journal.state.loginSubmitted)
        XCTAssertFalse(journal.state.publishAttempted)
        XCTAssertFalse(journal.state.completed.contains("login"))
        XCTAssertNoThrow(try ThreadsSession.checkVerification([["label": "Profile"]], journal: journal))
    }

    func testInstallationPreflightDistinguishesMissingFromUnavailable() throws {
        XCTAssertNoThrow(try ThreadsWorkflow.requireInstalled {
            ["apps": [["bundle_id": "com.burbn.barcelona"]]]
        })
        for apps: [[String: Any]] in [[], [["bundle_id": "com.burbn.instagram"]]] {
            XCTAssertThrowsError(try ThreadsWorkflow.requireInstalled { ["apps": apps] }) {
                XCTAssertEqual(String(describing: $0), "此虚拟机尚未安装 Threads，请先在应用管理中安装后重试同一任务。")
            }
        }
        for response: [String: Any] in [[:], ["apps": "invalid"], ["apps": [["name": "Threads"]]]] {
            XCTAssertThrowsError(try ThreadsWorkflow.requireInstalled { response }) {
                XCTAssertTrue(String(describing: $0).contains("响应格式异常"))
                XCTAssertFalse(String(describing: $0).contains("尚未安装"))
            }
        }
        XCTAssertThrowsError(try ThreadsWorkflow.requireInstalled { throw Failure("连接超时") }) {
            XCTAssertEqual(String(describing: $0), "无法检查 Threads 是否已安装：连接超时")
        }
    }

    func testPixelMatchingSurvivesThumbnailAndSmallSelectionBadge() throws {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let original = try XCTUnwrap(CGContext(data: nil, width: 160, height: 90, bitsPerComponent: 8,
            bytesPerRow: 640, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        original.setFillColor(CGColor(red: 0.9, green: 0.8, blue: 0.4, alpha: 1))
        original.fill(CGRect(x: 0, y: 0, width: 160, height: 90))
        original.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 0.2, alpha: 1))
        original.fill(CGRect(x: 40, y: 20, width: 40, height: 50))
        let image = try XCTUnwrap(original.makeImage())
        let thumb = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
            bytesPerRow: 256, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        thumb.draw(try XCTUnwrap(image.cropping(to: CGRect(x: 35, y: 0, width: 90, height: 90))),
                   in: CGRect(x: 0, y: 0, width: 64, height: 64))
        thumb.setFillColor(CGColor(gray: 1, alpha: 1))
        thumb.fillEllipse(in: CGRect(x: 54, y: 54, width: 8, height: 8))
        let score = ThreadsOriginalPhoto.distance(try ThreadsOriginalPhoto.pixels(image),
            try ThreadsOriginalPhoto.pixels(XCTUnwrap(thumb.makeImage())))
        XCTAssertLessThan(score, 0.08)
        XCTAssertEqual(try ThreadsOriginalPhoto.uniqueIndex(distances: [score, 0.3]), 0)
        XCTAssertThrowsError(try ThreadsOriginalPhoto.uniqueIndex(distances: [score, score]))
    }

    func testPhotoCellRoundingDoesNotExcludeFirstColumn() throws {
        let rect = try XCTUnwrap(ThreadsOriginalPhoto.cropRect(
            frame: ["x": -0.000003390842, "y": 304.333, "width": 142.222, "height": 142.333], width: 1290, height: 2796))
        XCTAssertEqual(rect.minX, 0)
        XCTAssertGreaterThan(rect.width, 426)
        XCTAssertNil(ThreadsOriginalPhoto.cropRect(
            frame: ["x": -10, "y": 304, "width": 142, "height": 142], width: 1290, height: 2796))
    }

    func testOriginalPhotoSelectionRejectsMissingOrAmbiguousMatches() throws {
        XCTAssertEqual(try ThreadsOriginalPhoto.uniqueIndex(distances: [0.8, 0.05, 0.7]), 1)
        // Real original in the Threads square picker, compared as normalized RGB pixels.
        XCTAssertEqual(try ThreadsOriginalPhoto.uniqueIndex(distances: [0.012542, 0.261248, 0.258359]), 0)
        XCTAssertThrowsError(try ThreadsOriginalPhoto.uniqueIndex(distances: []))
        XCTAssertThrowsError(try ThreadsOriginalPhoto.uniqueIndex(distances: [0.6]))
        XCTAssertThrowsError(try ThreadsOriginalPhoto.uniqueIndex(distances: [0.08, 0.09]))
    }
    func testTaskRetryCannotChangeImageOrCaption() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RunJournal(directory: directory, socket: directory.appendingPathComponent("vphone.sock").path,
                                     account: "test409518", freshLogin: false, platform: "threads")
        let image = directory.appendingPathComponent("fixture.png")
        try Data("original".utf8).write(to: image)
        let request = ThreadsTaskRequest(account: "test409518", socket: journal.state.socket, marker: "VPHONE-1234ABCD", caption: "first")
        try ThreadsTaskBinding.bind(request, journal: journal)
        try journal.checkpoint()
        XCTAssertNoThrow(try ThreadsTaskBinding.bind(request, journal: journal))
        XCTAssertThrowsError(try journal.checkpoint())
        let changed = ThreadsTaskRequest(account: request.account, socket: request.socket, marker: request.marker, caption: "changed")
        XCTAssertThrowsError(try ThreadsTaskBinding.bind(changed, journal: journal))
        try Data("changed".utf8).write(to: image)
        XCTAssertThrowsError(try ThreadsTaskBinding.bind(request, journal: journal))
    }
    func testBothPhotoLayoutsRequireActualAttachments() {
        XCTAssertEqual(ThreadsPost.attachmentCount([["label": "Remove photo at attached item #1"]]), 1)
        XCTAssertEqual(ThreadsPost.attachmentCount([["label": "Remove media"], ["identifier": "image-view"]]), 1)
        XCTAssertEqual(ThreadsPost.attachmentCount([["label": "Remove media"], ["identifier": "image-view"],
                                                    ["identifier": "image-view"]]), 2)
        XCTAssertEqual(ThreadsPost.attachmentCount([["label": "Add photos and videos from your camera roll"]]), 0)
        XCTAssertEqual(ThreadsPost.attachmentCount([["identifier": "image-view"]]), 0)
    }
    func testFixtureMarkerSurvivesPhotoThumbnail() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let marker = "VPHONE-46E4855F" // This exact marker failed text OCR in the real picker.
        try Fixture.create(marker: marker, at: url, title: "Threads automation", markerSize: 80, barcode: true)
        let source = try XCTUnwrap(NSImage(contentsOf: url))
        let thumbnail = NSImage(size: NSSize(width: 322, height: 322))
        thumbnail.lockFocus()
        source.draw(in: NSRect(x: 0, y: 0, width: 322, height: 322))
        thumbnail.unlockFocus()
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(data: XCTUnwrap(thumbnail.tiffRepresentation)).perform([request])
        XCTAssertEqual((request.results ?? []).compactMap(\.payloadStringValue), [marker])
    }
    func testRestartPreservesBioAndPlatformAndPublicationGuard() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let socket = directory.appendingPathComponent("vm.sock").path
        var journal: RunJournal? = try RunJournal(directory: directory, socket: socket, account: "test409518",
                                                 freshLogin: true, platform: "threads")
        journal!.state.originalBio = "original\n简介"
        journal!.state.bioChanged = true
        try journal!.checkpoint()
        journal = nil
        XCTAssertThrowsError(try RunJournal(directory: directory, socket: socket, account: "test409518", freshLogin: true))
        let resumed = try RunJournal(directory: directory, socket: socket, account: "test409518", freshLogin: true, platform: "threads")
        XCTAssertEqual(resumed.state.originalBio, "original\n简介")
        XCTAssertTrue(resumed.state.bioChanged)
        XCTAssertThrowsError(try resumed.checkpoint())
    }
    func testPlatformBindingRejectsLegacyInstagramState() throws {
        let state = RunState(socket: "/vm", account: "test409518", marker: "VPHONE-TEST", freshLogin: false)
        XCTAssertThrowsError(try state.validate(socket: "/vm", account: "test409518", freshLogin: false, platform: "threads"))
        XCTAssertNoThrow(try state.validate(socket: "/vm", account: "test409518", freshLogin: false))
    }
    func testBioBackupPreservesContentAndRefusesAmbiguousUI() throws {
        XCTAssertEqual(try ThreadsSession.bio(from: [["label": "Bio: + Write bio"]]), "")
        XCTAssertEqual(try ThreadsSession.bio(from: [["label": "Bio: line 1\nline 2"]]), "line 1\nline 2")
        XCTAssertThrowsError(try ThreadsSession.bio(from: []))
        XCTAssertThrowsError(try ThreadsSession.bio(from: [["label": "Bio: first"], ["label": "Bio: second"]]))
    }
    func testCaptionMarkerCannotPassImageVerification() {
        let caption = CGRect(x: 60, y: 300, width: 358, height: 68)
        let words = [("VPHONE-TEST", CGRect(x: 0.2, y: 0.64, width: 0.2, height: 0.02)),
                     ("Threads automation", CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.02))]
        XCTAssertFalse(ThreadsPost.markerIsInImage(words: words, marker: "VPHONE-TEST", captionFrame: caption))
        let withImage = words + [("VPHONE-TEST", CGRect(x: 0.2, y: 0.3, width: 0.2, height: 0.02))]
        XCTAssertTrue(ThreadsPost.markerIsInImage(words: withImage, marker: "VPHONE-TEST", captionFrame: caption))
        XCTAssertFalse(ThreadsPost.markerIsInImage(words: withImage, marker: "VPHONE-OTHER", captionFrame: caption))
    }
}
#endif
