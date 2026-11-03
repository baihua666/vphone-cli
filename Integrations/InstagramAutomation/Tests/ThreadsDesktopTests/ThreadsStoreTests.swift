import XCTest
import AppKit
import Vision
@testable import ThreadsDesktop
#if VPHONE_CUSTOM_THREADS_DESKTOP
@MainActor final class ThreadsStoreTests: XCTestCase {
    func testTextOnlyTaskPersistsWithoutImageAndRejectsEmptyContent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ThreadsStore(root: root, credentials: root.appendingPathComponent("credentials"))
        try store.saveAccount(username: "test409518", machinePath: "/example/vm", password: "test-secret")
        let account = try XCTUnwrap(store.accounts.first)
        XCTAssertThrowsError(try store.create(account: account, image: nil, caption: " \n", freshLogin: false, testProfile: false))
        let task = try store.create(account: account, image: nil, caption: "text only", freshLogin: false, testProfile: false)
        XCTAssertFalse(task.request.includesImage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory(task.id).appendingPathComponent("fixture.png").path))
        let reopened = try ThreadsStore(root: root, credentials: store.credentials)
        XCTAssertFalse(try XCTUnwrap(reopened.tasks.first).request.includesImage)
        let legacy = ThreadsTaskRequest(account: account.username, socket: "/example/vm/vphone.sock", marker: "VPHONE-1234ABCD", caption: "")
        XCTAssertNoThrow(try legacy.validate()) // Images need no user caption.
        XCTAssertTrue(try JSONDecoder().decode(ThreadsTaskRequest.self, from: JSONEncoder().encode(legacy)).includesImage)
    }
    func testPersistenceFrozenTaskAndCrashRecovery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ThreadsStore(root: root, credentials: root.appendingPathComponent("credentials"))
        try store.saveAccount(username: "test409518", machinePath: "/example/vm", password: "test-secret")
        try store.saveAccount(username: "test409518", machinePath: "/example/vm", password: "")
        let image = NSImage(size: NSSize(width: 800, height: 600))
        image.lockFocus(); NSColor.blue.setFill(); NSRect(x: 0, y: 0, width: 800, height: 600).fill(); image.unlockFocus()
        let input = root.appendingPathComponent("input.tiff")
        try XCTUnwrap(image.tiffRepresentation).write(to: input)
        let task = try store.create(account: store.accounts[0], image: input, caption: "hello", freshLogin: false, testProfile: false)
        let requestBefore = try Data(contentsOf: store.directory(task.id).appendingPathComponent("request.json"))
        try store.update(task.id, status: "运行中", detail: "publish: started")
        let reopened = try ThreadsStore(root: root, credentials: store.credentials)
        XCTAssertEqual(reopened.accounts.count, 1)
        XCTAssertEqual(reopened.tasks[0].id, task.id)
        XCTAssertEqual(reopened.tasks[0].status, "已中断")
        XCTAssertEqual(try Data(contentsOf: store.directory(task.id).appendingPathComponent("request.json")), requestBefore)
        XCTAssertFalse(try String(contentsOf: root.appendingPathComponent("accounts.json"), encoding: .utf8).contains("test-secret"))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: store.credentials.appendingPathComponent("test409518.password").path)[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(try Data(contentsOf: store.directory(task.id).appendingPathComponent(task.request.imageName)),
                       try Data(contentsOf: input))
        XCTAssertEqual(task.request.publishedCaption, "hello")
    }
    func testPublishedTextIsExactAndFull500CharactersAreAvailable() throws {
        for text in ["", "  原文\n换行  ", "VPHONE-用户自己填写", String(repeating: "字", count: 500)] {
            let request = ThreadsTaskRequest(account: "test409518", socket: "/vm/vphone.sock", marker: "VPHONE-1234ABCD", caption: text)
            XCTAssertEqual(request.publishedCaption, text)
            XCTAssertNoThrow(try request.validate())
        }
        let tooLong = ThreadsTaskRequest(account: "test409518", socket: "/vm/vphone.sock", marker: "VPHONE-1234ABCD", caption: String(repeating: "字", count: 501))
        XCTAssertThrowsError(try tooLong.validate())
    }
    func testInvalidInputAndCorruptStoreAreNotOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ThreadsStore(root: root, credentials: root.appendingPathComponent("credentials"))
        XCTAssertThrowsError(try store.saveAccount(username: "../bad", machinePath: "/vm", password: "x"))
        XCTAssertThrowsError(try store.saveAccount(username: "valid", machinePath: "/vm", password: ""))
        let corrupt = Data("broken".utf8)
        try corrupt.write(to: root.appendingPathComponent("tasks.json"))
        XCTAssertThrowsError(try ThreadsStore(root: root, credentials: store.credentials))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("tasks.json")), corrupt)
    }
}
#endif
