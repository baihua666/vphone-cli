import XCTest
@testable import VPhoneDistribution

@MainActor final class SetupProgressTests: XCTestCase {
    func testFailureThenRetryDoesNotEraseCompletedPrerequisites() async throws {
        let progress = DistributionSetupProgress()
        try await progress.perform(.core, scope: "core-a") {}
        do {
            try await progress.perform(.image, scope: "image-a") {
                XCTAssertEqual(progress.state(.image, scope: "image-a"), .running)
                throw DistributionError("校验失败")
            }
            XCTFail("must propagate failure")
        } catch {}
        XCTAssertEqual(progress.state(.image, scope: "image-a"), .failed("校验失败"))
        XCTAssertEqual(progress.state(.core, scope: "core-a"), .completed)
        let url = try await progress.perform(.image, scope: "image-a") { URL(fileURLWithPath: "/verified") }
        XCTAssertEqual(url.path, "/verified")
        XCTAssertEqual(progress.state(.image, scope: "image-a"), .completed)
        XCTAssertEqual(progress.state(.launch, scope: "image-a|/vm/one"), .pending)
    }

    func testSwitchingImageOrInstanceDoesNotReuseCompletion() async throws {
        let progress = DistributionSetupProgress()
        try await progress.perform(.image, scope: "image-a-hash") {}
        try await progress.perform(.launch, scope: "image-a-hash|/library/one") {}
        XCTAssertEqual(progress.state(.image, scope: "image-b-hash"), .pending)
        XCTAssertEqual(progress.state(.launch, scope: "image-a-hash|/library/two"), .pending)
        XCTAssertEqual(progress.state(.launch, scope: "image-b-hash|/library/one"), .pending)
        XCTAssertEqual(progress.state(.launch, scope: "image-a-hash|/other-library/one"), .pending)
        XCTAssertEqual(progress.state(.launch, scope: "image-a-hash|/library/one"), .completed)
        // Relaunch must recheck files/guest, not restore successful UI flags.
        XCTAssertEqual(DistributionSetupProgress().state(.image, scope: "image-a-hash"), .pending)
    }

    func testCancellationIsPausedAndCanResume() async throws {
        let progress = DistributionSetupProgress()
        do {
            try await progress.perform(.image, scope: "image") { throw CancellationError() }
            XCTFail("must propagate cancellation")
        } catch {}
        XCTAssertEqual(progress.state(.image, scope: "image"), .paused)
        try await progress.perform(.image, scope: "image") {}
        XCTAssertEqual(progress.state(.image, scope: "image"), .completed)
    }

    func testCancelledTaskCannotReportCompletionEvenIfOperationReturns() async {
        let progress = DistributionSetupProgress()
        let task = Task { @MainActor in
            try await progress.perform(.launch, scope: "vm") {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        do { try await task.value; XCTFail("cancelled task completed") } catch {}
        XCTAssertEqual(progress.state(.launch, scope: "vm"), .paused)
    }
}

extension DistributionTests {
    @MainActor func testLocalImageFailureCanRetryWithoutFalseCompletion() async throws {
        let folder = try temp(), image = try catalog().images[0]
        let file = folder.appendingPathComponent("local.tzst")
        try Data("badbad".utf8).write(to: file)
        let download = DistributionDownload(root: folder.appendingPathComponent("cache")) { _ in
            XCTFail("no image network"); throw DistributionError("unexpected")
        }
        let progress = DistributionSetupProgress()
        do {
            _ = try await progress.perform(.image, scope: image.cacheKey) {
                try await download.image(image, tag: "local", localArchive: file)
            }
            XCTFail("tampered file must fail")
        } catch {}
        if case .failed = progress.state(.image, scope: image.cacheKey) {} else { XCTFail("must remain failed") }
        try Data("onetwo".utf8).write(to: file)
        let archive = try await progress.perform(.image, scope: image.cacheKey) {
            try await download.image(image, tag: "local", localArchive: file)
        }
        XCTAssertEqual(archive, file)
        XCTAssertEqual(progress.state(.image, scope: image.cacheKey), .completed)
        XCTAssertEqual(progress.state(.launch, scope: "new-instance"), .pending)
    }
}
