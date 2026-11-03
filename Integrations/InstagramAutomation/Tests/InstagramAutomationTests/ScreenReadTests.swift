import XCTest
@testable import InstagramAutomation
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION
final class ScreenReadTests: XCTestCase {
    func testShareSheetAXTransitionCanRecoverAfterThreeReads() throws {
        var reads = 0
        _ = try Screen.readTree(read: {
            reads += 1
            if reads < 6 { throw Failure("AX element query failed (-25216)") }
            return [["label": "Image canvas"]]
        }, pause: {})
        XCTAssertEqual(reads, 6)
        reads = 0
        XCTAssertThrowsError(try Screen.readTree(read: {
            reads += 1; throw Failure("AX element query failed (-25216)")
        }, pause: {}))
        XCTAssertEqual(reads, 10)
    }

    func testTransientTreeFailureRecoversWithoutRepeatingActions() throws {
        var reads = 0
        var pauses = 0
        let result = try Screen.readTree(read: {
            reads += 1
            if reads < 3 { throw Failure("AX temporarily unavailable") }
            return [["label": "Profile"]]
        }, pause: { pauses += 1 })
        XCTAssertEqual(reads, 3)
        XCTAssertEqual(pauses, 2)
        XCTAssertEqual(result.first?["label"] as? String, "Profile")
    }

    func testAppRestartAXTransitionCanRecover() throws {
        var reads = 0
        _ = try Screen.readTree(read: {
            reads += 1
            if reads < 5 { throw Failure("AX element query failed (-25215)") }
            return [["label": "Profile"]]
        }, pause: {})
        XCTAssertEqual(reads, 5)
    }

    func testPersistentFailureStopsAndKeepsOriginalReason() {
        var reads = 0
        XCTAssertThrowsError(try Screen.readTree(read: {
            reads += 1
            throw Failure("specific guest error")
        }, pause: {})) { error in
            XCTAssertTrue(String(describing: error).contains("specific guest error"))
        }
        XCTAssertEqual(reads, 3)
    }

    func testSuccessfulReadIsNotRepeated() throws {
        var reads = 0
        _ = try Screen.readTree(read: { reads += 1; return [] }, pause: { XCTFail("unexpected retry") })
        XCTAssertEqual(reads, 1)
    }
}
#endif
