import XCTest
@testable import VPhoneDistribution

extension DistributionTests {
    func testLocalImageUsesOriginalFileWithoutDownloadOrCacheCopy() async throws {
        let folder = try temp()
        let file = folder.appendingPathComponent("镜像 file.tzst")
        let bytes = Data("onetwo".utf8)
        try bytes.write(to: file)
        let value = try catalog()
        let image = try XCTUnwrap(value.images.first)
        let cache = folder.appendingPathComponent("cache")
        let download = DistributionDownload(root: cache) { _ in
            XCTFail("Local selection must never fetch")
            throw DistributionError("unexpected download")
        }
        let result = try await download.image(image, tag: value.tag, localArchive: file)
        XCTAssertEqual(result, file)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        // Revalidate before import, even when this path previously passed.
        try Data("badbad".utf8).write(to: file)
        do {
            _ = try await download.image(image, tag: value.tag, localArchive: file)
            XCTFail("Changed file must fail SHA-256")
        } catch { XCTAssertTrue(error.localizedDescription.contains("SHA-256")) }
        try bytes.write(to: file)
        let retry = try await download.image(image, tag: value.tag, localArchive: file)
        XCTAssertEqual(retry, file)
    }

    func testInvalidLocalImagesNeverFallBackToNetwork() async throws {
        let folder = try temp()
        let value = try catalog()
        let image = try XCTUnwrap(value.images.first)
        let short = folder.appendingPathComponent("short.tzst")
        try Data("one".utf8).write(to: short)
        let link = folder.appendingPathComponent("link.tzst")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: short)
        let download = DistributionDownload(root: folder.appendingPathComponent("cache")) { _ in
            XCTFail("Invalid local selection must not fetch")
            throw DistributionError("unexpected download")
        }
        for file in [folder.appendingPathComponent("missing.tzst"), short, folder, link,
                     URL(string: "https://example.com/image.tzst")!] {
            do {
                _ = try await download.image(image, tag: value.tag, localArchive: file)
                XCTFail("Invalid local image accepted: \(file)")
            } catch { /* Retrying another file remains possible. */ }
        }
    }
}
