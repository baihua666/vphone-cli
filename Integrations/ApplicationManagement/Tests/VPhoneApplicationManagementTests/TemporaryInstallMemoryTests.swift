import XCTest
@testable import VPhoneApplicationManagement

final class TemporaryInstallMemoryTests: XCTestCase {
    @MainActor final class Machine {
        var memory = 3072
        var running = true
        var installed = false
        var record = false
        var calls: [String] = []
        var failAt: String?

        func step(_ name: String) throws {
            calls.append(name)
            if failAt == name { throw NSError(domain: name, code: 1) }
        }
        func prepare() throws {
            record = true
            try step("stop")
            running = false
            try step("increase")
            memory = 8192
            try step("start")
            running = true
            try step("ready")
        }
        func install() throws {
            try step("install")
            installed = true
        }
        func restore() throws {
            XCTAssertFalse(Task.isCancelled)
            try step("restore")
            running = false
            memory = 3072
            try step("restart")
            running = true
            record = false
        }
    }

    @MainActor func testSuccessRestoresActualOriginalMemory() async throws {
        let machine = Machine()
        try await VPhoneTemporaryInstallMemory.run(prepare: { try machine.prepare() }, install: { try machine.install() }, restore: { try machine.restore() })
        XCTAssertEqual(machine.memory, 3072)
        XCTAssertTrue(machine.running)
        XCTAssertTrue(machine.installed)
        XCTAssertFalse(machine.record)
        XCTAssertEqual(machine.calls, ["stop", "increase", "start", "ready", "install", "restore", "restart"])
    }

    @MainActor func testEveryPartialFailureRestoresWithoutRetryingInstall() async {
        for phase in ["stop", "increase", "start", "ready", "install"] {
            let machine = Machine(); machine.failAt = phase
            do {
                try await VPhoneTemporaryInstallMemory.run(prepare: { try machine.prepare() }, install: { try machine.install() }, restore: { try machine.restore() })
                XCTFail("Should fail at \(phase)")
            } catch { XCTAssertTrue(error.localizedDescription.contains("原内存已恢复")) }
            XCTAssertEqual(machine.memory, 3072)
            XCTAssertTrue(machine.running)
            XCTAssertFalse(machine.record)
            XCTAssertLessThanOrEqual(machine.calls.filter { $0 == "install" }.count, 1)
        }
    }

    @MainActor func testFailedRecoveryRetainsRecordAndReportsFailure() async {
        for phase in ["restore", "restart"] {
            let machine = Machine(); machine.failAt = phase
            do {
                try await VPhoneTemporaryInstallMemory.run(prepare: { try machine.prepare() }, install: { try machine.install() }, restore: { try machine.restore() })
                XCTFail("Recovery must fail")
            } catch { XCTAssertTrue(error.localizedDescription.contains("恢复记录已保留")) }
            XCTAssertTrue(machine.record)
        }
    }

    @MainActor func testCancellationDoesNotCancelRestoration() async {
        let machine = Machine()
        let task = Task { @MainActor in
            try await VPhoneTemporaryInstallMemory.run(prepare: {
                try machine.prepare()
                withUnsafeCurrentTask { $0?.cancel() }
            }, install: { XCTFail("Cancelled work must not install") }, restore: { try machine.restore() })
        }
        do { try await task.value; XCTFail("Cancellation must be reported") } catch {}
        XCTAssertEqual(machine.memory, 3072)
        XCTAssertTrue(machine.running)
        XCTAssertFalse(machine.record)
    }

    func testRecoveryRecordPersistsAcrossReopenAndCannotOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("recovery.json")
        XCTAssertNil(try VPhoneInstallMemoryRecord.read(from: url))
        let record = VPhoneInstallMemoryRecord(libraryRoot: "/isolated/library", name: "same-name", directoryIdentity: "disk:inode", bundle: "2.8.0-local.testfixture", originalMemoryMB: 3072)
        try record.save(to: url)
        let reopened = try XCTUnwrap(VPhoneInstallMemoryRecord.read(from: url))
        XCTAssertEqual(reopened.originalMemoryMB, 3072)
        XCTAssertEqual(reopened.libraryRoot, "/isolated/library")
        XCTAssertEqual(reopened.directoryIdentity, "disk:inode")
        XCTAssertThrowsError(try record.save(to: url))
        try Data("corrupt".utf8).write(to: url)
        XCTAssertThrowsError(try VPhoneInstallMemoryRecord.read(from: url))
    }
}
