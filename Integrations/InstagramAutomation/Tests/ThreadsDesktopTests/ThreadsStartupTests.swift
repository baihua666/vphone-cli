import XCTest
@testable import ThreadsDesktop
#if VPHONE_CUSTOM_THREADS_DESKTOP
@MainActor final class ThreadsStartupTests: XCTestCase {
    func testPreparationFailurePreservesTaskAndPublicationStateAndBlocksSecondRun() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ThreadsDesktopModel(root: root, credentials: root.appendingPathComponent("credentials"))
        model.saveAccount(username: "test409518", machinePath: "/example/vm", password: "test-secret")
        let id = try XCTUnwrap(model.create(account: try XCTUnwrap(model.accounts.first), image: nil,
            caption: "hello", freshLogin: false, testProfile: false))
        let folder = try XCTUnwrap(model.directory(id))
        let request = try Data(contentsOf: folder.appendingPathComponent("request.json"))
        let checkpoint = Data("{\"publishAttempted\":true}".utf8)
        try checkpoint.write(to: folder.appendingPathComponent("state.json"))
        var secondPrepared = false
        await model.run(id, executable: URL(fileURLWithPath: "/missing-runner")) {
            XCTAssertEqual(model.running, id)
            await model.run(id, executable: URL(fileURLWithPath: "/missing-runner")) { secondPrepared = true }
            throw ThreadsDesktopError("启动失败测试")
        }
        XCTAssertFalse(secondPrepared)
        XCTAssertNil(model.running)
        XCTAssertEqual(model.error, "启动失败测试")
        XCTAssertEqual(model.tasks.first?.status, "启动未就绪")
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("request.json")), request)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("state.json")), checkpoint)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("run.log").path))
        var preparedAgain = false
        await model.run(id, executable: URL(fileURLWithPath: "/missing-runner")) { preparedAgain = true }
        XCTAssertTrue(preparedAgain)
        XCTAssertTrue(model.error.contains("执行器缺失"))
    }
}
#endif
