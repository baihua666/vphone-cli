import XCTest
@testable import ThreadsDesktop
#if VPHONE_CUSTOM_THREADS_DESKTOP
@MainActor final class ThreadsStartupTests: XCTestCase {
    func testStopRunnerPreservesPublicationCheckpoint() async throws {
        for attempted in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let model = ThreadsDesktopModel(root: root, credentials: root.appendingPathComponent("credentials"))
            model.saveAccount(username: "test409518", machinePath: "/example/vm", password: "test")
            let id = try XCTUnwrap(model.create(account: try XCTUnwrap(model.accounts.first), image: nil,
                caption: "test", freshLogin: false, testProfile: false))
            let folder = try XCTUnwrap(model.directory(id))
            let checkpoint = Data("{\"publishAttempted\":\(attempted)}".utf8)
            try checkpoint.write(to: folder.appendingPathComponent("state.json"))
            let runner = root.appendingPathComponent("test-runner")
            try Data("#!/bin/sh\nexec /bin/sleep 30\n".utf8).write(to: runner)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runner.path)
            model.run(id, executable: runner)
            XCTAssertEqual(model.running, id)
            model.stop()
            let deadline = Date().addingTimeInterval(5)
            while model.running != nil && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
            XCTAssertNil(model.running)
            XCTAssertEqual(model.tasks.first?.status, attempted ? "发布结果待核验" : "已中止")
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("state.json")), checkpoint)
        }
    }
    func testStopPreparationDoesNotStartRunner() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ThreadsDesktopModel(root: root, credentials: root.appendingPathComponent("credentials"))
        model.saveAccount(username: "test409518", machinePath: "/example/vm", password: "test")
        let id = try XCTUnwrap(model.create(account: try XCTUnwrap(model.accounts.first), image: nil,
            caption: "test", freshLogin: false, testProfile: false))
        await model.run(id, executable: URL(fileURLWithPath: "/missing-runner")) {
            model.stop()
            try Task.checkCancellation()
        }
        XCTAssertNil(model.running)
        XCTAssertEqual(model.tasks.first?.status, "已中止")
        XCTAssertTrue(model.error.isEmpty)
    }

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
        XCTAssertEqual(model.tasks.first?.status, "发布结果待核验")
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
