import XCTest
import AppKit
import Vision
import ThreadsDesktop
@testable import InstagramAutomation
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION && VPHONE_CUSTOM_THREADS_AUTOMATION
final class ThreadsTests: XCTestCase {
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

    func testOriginalPhotoSelectionRejectsMissingOrAmbiguousMatches() throws {
        XCTAssertEqual(try ThreadsOriginalPhoto.uniqueIndex(distances: [0.8, 0.05, 0.7]), 1)
        XCTAssertThrowsError(try ThreadsOriginalPhoto.uniqueIndex(distances: []))
        XCTAssertThrowsError(try ThreadsOriginalPhoto.uniqueIndex(distances: [0.4]))
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
