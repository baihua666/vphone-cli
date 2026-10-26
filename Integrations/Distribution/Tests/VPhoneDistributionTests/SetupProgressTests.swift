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
    @MainActor func testWizardDownloadFailureRetriesVerifiedChunksWithoutFalseCompletion() async throws {
        let folder = try temp()
        let value = try catalog()
        let image = value.images[0]
        let source = Fixture(folder: folder, data: [Data("one".utf8), Data("two".utf8)])
        await source.failSecond()
        let download = DistributionDownload(root: folder.appendingPathComponent("cache")) { try await source.fetch($0) }
        let progress = DistributionSetupProgress()
        do {
            _ = try await progress.perform(.image, scope: image.cacheKey) {
                try await download.image(image, tag: value.tag)
            }
            XCTFail("interrupted transfer must fail")
        } catch {}
        XCTAssertEqual(progress.state(.image, scope: image.cacheKey), .failed("network interrupted"))
        let archive = try await progress.perform(.image, scope: image.cacheKey) {
            try await download.image(image, tag: value.tag)
        }
        XCTAssertEqual(try DistributionDownload.digest(archive), image.archiveSHA256)
        XCTAssertEqual(progress.state(.image, scope: image.cacheKey), .completed)
        let calls = await source.calls
        XCTAssertEqual(calls, ["part0", "part1", "part1"])
        XCTAssertEqual(progress.state(.launch, scope: "new-instance"), .pending)
    }
}
