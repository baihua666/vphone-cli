import XCTest
@testable import InstagramAutomation
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION
final class RunnerTests: XCTestCase {
    func testSlowTypingAndCaptionFailurePreventPublishing() throws {
        var delay: Int?
        var published = false
        let runner = Runner(rpc: { method, params in
            if method == "input.type" { delay = params["delay_ms"] as? Int }
            if method == "ui.wait" { throw Failure("caption mismatch") }
        }, secret: { _ in "" }, checkpoint: { published = true }, report: { _, _ in })
        let flow = Flow(steps: [
            .init(id: "caption", action: "type", text: "expected caption", delayMs: 100),
            .init(id: "readback", action: "wait", text: "expected caption"),
            .init(id: "publish", action: "publish", text: "Post"),
            .init(id: "verify", action: "wait", text: "posted")])
        XCTAssertThrowsError(try runner.run(flow))
        XCTAssertEqual(delay, 100)
        XCTAssertFalse(published)
        XCTAssertThrowsError(try Flow(steps: [.init(id: "bad", action: "type", text: "x", delayMs: -1)]).validate())
    }
    func testVisualPublishCheckpointAndFailureStop() throws {
        var events: [String] = []
        let runner = Runner(rpc: { method, _ in events.append(method) }, secret: { _ in "" },
                            checkpoint: { events.append("checkpoint"); throw Failure("disk full") }, report: { _, _ in })
        XCTAssertThrowsError(try runner.run(Flow(steps: [.init(id: "publish", action: "visualPublish", text: "Share"),
                                                        .init(id: "verify", action: "visualWait", text: "Post shared")])))
        XCTAssertEqual(events, ["host.visual.wait", "checkpoint"])
    }
    func testClearUsesSelectionBeforeDeletion() throws {
        var keys: [String] = []
        let runner = Runner(rpc: { _, params in keys.append(params["name"] as! String) }, secret: { _ in "" },
                            checkpoint: {}, report: { _, _ in })
        try runner.run(Flow(steps: [.init(id: "clear", action: "clear")]))
        XCTAssertEqual(keys, ["cmd+a", "backspace"])
    }
    func testWaitBeforeTapAndStopOnFailure() throws {
        var calls: [String] = []
        let runner = Runner(rpc: { method, _ in
            calls.append(method)
            if method == "ui.wait" { throw Failure("secret echoed by guest") }
        }, secret: { _ in "password" }, checkpoint: {}, report: { _, _ in })
        XCTAssertThrowsError(try runner.run(Flow(steps: [.init(id: "tap", action: "tap", text: "Profile")]))) { error in
            XCTAssertFalse(String(describing: error).contains("secret echoed"))
        }
        XCTAssertEqual(calls, ["ui.wait"])
    }
    func testPublishCheckpointPrecedesMutation() throws {
        var events: [String] = []
        let runner = Runner(rpc: { method, _ in events.append(method) }, secret: { _ in "" },
                            checkpoint: { events.append("checkpoint") }, report: { _, _ in })
        try runner.run(Flow(steps: [.init(id: "publish", action: "publish", text: "Share"),
                                   .init(id: "verify", action: "wait", text: "unique post")]))
        XCTAssertEqual(events, ["ui.wait", "checkpoint", "ui.tap_element", "ui.wait"])
    }
    func testCheckpointFailurePreventsPublish() {
        var calls: [String] = []
        let runner = Runner(rpc: { method, _ in calls.append(method) }, secret: { _ in "" },
                            checkpoint: { throw Failure("disk full") }, report: { _, _ in })
        XCTAssertThrowsError(try runner.run(Flow(steps: [.init(id: "publish", action: "publish", text: "Share"),
                                                        .init(id: "verify", action: "wait", text: "post")])))
        XCTAssertEqual(calls, ["ui.wait"])
    }
    func testRejectInvalidFlows() {
        for flow in [Flow(steps: []), Flow(steps: [.init(id: "x", action: "arbitrary")]),
                     Flow(steps: [.init(id: "x", action: "tap")]),
                     Flow(steps: [.init(id: "x", action: "publish", text: "Share")])] {
            XCTAssertThrowsError(try flow.validate())
        }
    }
    func testSecretsOnlyReachTransport() throws {
        var events: [String] = []
        var typed = ""
        let runner = Runner(rpc: { _, params in typed = params["text"] as? String ?? "" },
                            secret: { _ in "test-only-secret" }, checkpoint: {},
                            report: { id, state in events.append(id + state) })
        try runner.run(Flow(steps: [.init(id: "password", action: "secret", secretAccount: "qa")]))
        XCTAssertEqual(typed, "test-only-secret")
        XCTAssertFalse(events.joined().contains("test-only-secret"))
    }
}
#endif
