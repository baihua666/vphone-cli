import XCTest
import Foundation
@testable import ThreadsDesktop
#if VPHONE_CUSTOM_THREADS_DESKTOP
final class PhotoValidationModeTests: XCTestCase {
    @MainActor func testValidationPreservesPublicationRecord() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ThreadsStore(root: root, credentials: root.appendingPathComponent("credentials"))
        try store.saveAccount(username: "test", machinePath: "/example/vm", password: "test-only")
        let task = try store.create(account: store.accounts[0], image: nil, caption: "test", freshLogin: false, testProfile: false)
        try store.update(task.id, status: "发布结果待核验", detail: "original publication log")
        let before = try Data(contentsOf: root.appendingPathComponent("tasks.json"))
        let executable = root.appendingPathComponent("validation-stub")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let model = ThreadsDesktopModel(root: root, credentials: store.credentials)
        model.run(task.id, executable: executable, mode: .photoValidation)
        for _ in 0..<40 where model.running != nil { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertNil(model.running)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("tasks.json")), before)
    }
    func testValidationCommandCannotRouteToPublishingTask() {
        XCTAssertEqual(ThreadsExecutionMode.photoValidation.arguments(directory: "/task"), ["threads-photo-check", "/task"])
        XCTAssertEqual(ThreadsExecutionMode.publish.arguments(directory: "/task"), ["threads-task", "/task"])
        XCTAssertEqual(ThreadsExecutionMode.photoValidation.resultStatus(success: true), "选图与附件核验通过（本次未发布）")
        XCTAssertEqual(ThreadsExecutionMode.photoValidation.resultStatus(success: false), "选图核验失败（本次未发布）")
    }
}
#endif
