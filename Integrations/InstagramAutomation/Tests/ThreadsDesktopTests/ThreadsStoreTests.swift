import XCTest
import AppKit
import Vision
@testable import ThreadsDesktop
#if VPHONE_CUSTOM_THREADS_DESKTOP
@MainActor final class ThreadsStoreTests: XCTestCase {
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
        XCTAssertEqual(try reopened.password(for: "test409518"), "test-secret")
        XCTAssertThrowsError(try reopened.password(for: "../bad"))
        XCTAssertEqual(reopened.tasks[0].id, task.id)
        XCTAssertEqual(reopened.tasks[0].status, "已中断")
        XCTAssertEqual(try Data(contentsOf: store.directory(task.id).appendingPathComponent("request.json")), requestBefore)
        XCTAssertFalse(try String(contentsOf: root.appendingPathComponent("accounts.json"), encoding: .utf8).contains("test-secret"))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: store.credentials.appendingPathComponent("test409518.password").path)[.posixPermissions] as? Int, 0o600)
        let prepared = try XCTUnwrap(NSImage(contentsOf: store.directory(task.id).appendingPathComponent("fixture.png")))
        let thumb = NSImage(size: NSSize(width: 322, height: 322))
        thumb.lockFocus(); prepared.draw(in: NSRect(x: 0, y: 0, width: 322, height: 322)); thumb.unlockFocus()
        let qr = VNDetectBarcodesRequest(); qr.symbologies = [.qr]
        try VNImageRequestHandler(data: XCTUnwrap(thumb.tiffRepresentation)).perform([qr])
        XCTAssertEqual(qr.results?.compactMap(\.payloadStringValue), [task.request.marker])
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
