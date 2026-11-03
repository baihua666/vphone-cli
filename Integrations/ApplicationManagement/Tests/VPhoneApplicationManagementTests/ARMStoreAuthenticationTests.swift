import XCTest
@testable import VPhoneApplicationManagement

final class ARMStoreAuthenticationTests: XCTestCase {
    @MainActor func testValidSessionDoesNotStartAuthorization() async throws {
        var starts = 0
        try await ARMStoreAuthentication.ensureSession(check: { true }, begin: { starts += 1 })
        XCTAssertEqual(starts, 0)
    }

    @MainActor func testManualWebsiteLoginResumesSameRequestWithoutPresetAccount() async throws {
        var starts = 0
        var checks = 0
        try await ARMStoreAuthentication.ensureSession(timeout: .seconds(1), interval: .milliseconds(1), check: {
            checks += 1
            // The website becomes authenticated after several checks, without a native confirm action.
            return checks == 4
        }, begin: { starts += 1 })
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(checks, 4)
    }

    @MainActor func testDismissedVerificationCancelsPendingDownload() async {
        var cancelled = false
        do {
            try await ARMStoreAuthentication.ensureSession(interval: .milliseconds(1), check: { false },
                begin: { cancelled = true }, cancelled: { cancelled })
            XCTFail("A dismissed verification must not allow downloading")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }

    @MainActor func testTimeoutDoesNotRestartAuthorization() async {
        var starts = 0
        do {
            try await ARMStoreAuthentication.ensureSession(timeout: .milliseconds(5), interval: .milliseconds(1),
                check: { false }, begin: { starts += 1 })
            XCTFail("Expected timeout")
        } catch is ARMStoreAuthenticationTimeout {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(starts, 1)
    }

    @MainActor func testCancellationDuringCheckCannotContinueDownload() async {
        var cancelled = false
        do {
            try await ARMStoreAuthentication.ensureSession(check: { cancelled = true; return true },
                begin: { XCTFail("Must not start authorization") }, cancelled: { cancelled })
            XCTFail("A late check result must not revive a cancelled operation")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
}
