import XCTest
@testable import InstagramAutomation
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION
final class WorkflowTests: XCTestCase {
    func testStateCannotMoveToAnotherAccountOrInstance() throws {
        let state = RunState(socket: "/a", account: "test409518", marker: "VPHONE-TEST", freshLogin: true)
        XCTAssertThrowsError(try state.validate(socket: "/b", account: "test409518", freshLogin: true))
        XCTAssertThrowsError(try state.validate(socket: "/a", account: "other", freshLogin: true))
        XCTAssertThrowsError(try state.validate(socket: "/a", account: "test409518", freshLogin: false))
        XCTAssertThrowsError(try state.validate(socket: "/a", account: "test409518", freshLogin: true, passwordLogin: true))
        XCTAssertNoThrow(try state.validate(socket: "/a", account: "test409518", freshLogin: true))
    }
    func testRestartKeepsPublishAttemptAndSkipsPassedStages() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let socket = directory.appendingPathComponent("vm.sock").path
        var journal: RunJournal? = try RunJournal(directory: directory, socket: socket, account: "test409518", freshLogin: true)
        try journal!.stage("login") {}
        try journal!.checkpoint()
        journal = nil
        let resumed = try RunJournal(directory: directory, socket: socket, account: "test409518", freshLogin: true)
        XCTAssertTrue(resumed.state.publishAttempted)
        XCTAssertThrowsError(try resumed.checkpoint())
        try resumed.stage("login") { XCTFail("不能重复执行已通过的阶段") }
    }
    func testFailedStageIsNotMarkedPassedAndInstanceLockExcludesSecondRunner() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let socket = directory.appendingPathComponent("vm.sock").path
        let journal = try RunJournal(directory: directory, socket: socket, account: "test409518", freshLogin: false)
        XCTAssertThrowsError(try journal.stage("import") { throw Failure("failed") })
        XCTAssertFalse(journal.state.completed.contains("import"))
        XCTAssertThrowsError(try RunJournal(directory: directory.appendingPathComponent("other"), socket: socket,
                                            account: "test409518", freshLogin: false))
    }
    func testChallengeClassificationDoesNotTreatOrdinaryLoginAsVerification() {
        XCTAssertTrue(Login.isChallenge("Enter the 6-digit code"))
        XCTAssertTrue(Login.isChallenge("Check your notifications on another device"))
        XCTAssertTrue(Login.isChallenge("Confirm your identity"))
        XCTAssertFalse(Login.isChallenge("Username Password Log in"))
        XCTAssertFalse(Login.isChallenge("Page isn't available right now"))
    }
}
#endif
