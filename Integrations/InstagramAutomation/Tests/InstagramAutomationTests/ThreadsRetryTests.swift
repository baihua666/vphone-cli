import XCTest
import ThreadsDesktop
@testable import InstagramAutomation
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION && VPHONE_CUSTOM_THREADS_AUTOMATION
final class ThreadsRetryTests: XCTestCase {
    func testTextOnlyCompletedRetryNeedsNeitherImageNorGuest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let socket = directory.appendingPathComponent("vphone.sock").path
        let request = ThreadsTaskRequest(account: "test409518", socket: socket, marker: "VPHONE-1234ABCD", caption: "text", hasImage: false)
        do {
            let journal = try RunJournal(directory: directory, socket: socket, account: request.account, freshLogin: false, platform: "threads")
            try ThreadsTaskBinding.bind(request, journal: journal)
            try journal.checkpoint()
            journal.state.completed = ["verify"]
            try journal.save()
            let changed = ThreadsTaskRequest(account: request.account, socket: socket, marker: request.marker, caption: "different", hasImage: false)
            XCTAssertThrowsError(try ThreadsTaskBinding.bind(changed, journal: journal))
        }
        XCTAssertNoThrow(try ThreadsWorkflow.run(socket: socket, directory: directory, freshLogin: false, password: nil, request: request))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("fixture.png").path))
    }
    func testPlatformLimitPersistsAndDoesNotExtendOnRetry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertNoThrow(try ThreadsRestriction.check(directory: directory))
        let elements: [[String: Any]] = [["label": "Try again in 24 hours"]]
        XCTAssertThrowsError(try ThreadsRestriction.inspect(elements, directory: directory))
        let file = directory.appendingPathComponent("retry-after.json")
        let before = try Data(contentsOf: file)
        XCTAssertThrowsError(try ThreadsRestriction.check(directory: directory))
        XCTAssertThrowsError(try ThreadsRestriction.inspect(elements, directory: directory))
        XCTAssertEqual(try Data(contentsOf: file), before)
    }
    func testCompletedTaskRetryReturnsBeforeGuestConnection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let socket = directory.appendingPathComponent("vphone.sock").path
        let request = ThreadsTaskRequest(account: "test409518", socket: socket, marker: "VPHONE-1234ABCD", caption: "test")
        do {
            let journal = try RunJournal(directory: directory, socket: socket, account: request.account, freshLogin: false, platform: "threads")
            try Data("image".utf8).write(to: directory.appendingPathComponent("fixture.png"))
            try ThreadsTaskBinding.bind(request, journal: journal)
            try journal.checkpoint()
            journal.state.completed = ["verify"]
            try journal.save()
        }
        XCTAssertNoThrow(try ThreadsWorkflow.run(socket: socket, directory: directory, freshLogin: false, password: nil, request: request))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("events.jsonl")).count, 0)
    }
}
#endif
