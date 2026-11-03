import XCTest
@testable import InstagramAutomation
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION && VPHONE_CUSTOM_THREADS_AUTOMATION
final class PhotoValidationTests: XCTestCase {
    func testValidationOnlySelectsConfirmsAndVerifies() throws {
        var actions: [String] = []
        try ThreadsPhotoValidation.execute(hasAttachment: { false }, openPicker: { actions.append("open") },
            select: { actions.append("select") }, confirm: { actions.append("done") }, verify: { actions.append("verify") })
        XCTAssertEqual(actions, ["open", "select", "done", "verify"])
    }
    func testExistingAttachmentOnlyVerifiesAndFailureStopsBeforeDone() throws {
        var actions: [String] = []
        try ThreadsPhotoValidation.execute(hasAttachment: { true }, openPicker: { XCTFail() }, select: { XCTFail() },
            confirm: { XCTFail() }, verify: { actions.append("verify") })
        XCTAssertEqual(actions, ["verify"])
        XCTAssertThrowsError(try ThreadsPhotoValidation.execute(hasAttachment: { false }, openPicker: {},
            select: { throw Failure("ambiguous") }, confirm: { XCTFail() }, verify: { XCTFail() }))
    }
}
#endif
