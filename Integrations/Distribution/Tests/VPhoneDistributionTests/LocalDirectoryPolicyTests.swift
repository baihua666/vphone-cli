import XCTest
@testable import VPhoneDistribution

extension DistributionTests {
    func testPublicationRejectsImagesAndUnlistedFiles() throws {
        let old = try catalog()
        XCTAssertThrowsError(try DistributionPublicationPolicy.validate(old, names: old.assets.map(\.name)))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        object["images"] = []
        let clean = try DistributionCatalog.decode(JSONSerialization.data(withJSONObject: object))
        let allowed = [clean.app.asset.name, clean.core.asset.name, GitHubDistribution.manifestName]
        XCTAssertNoThrow(try DistributionPublicationPolicy.validate(clean, names: allowed))
        for file in ["clean.part0000", "image.tzst", "Disk.img", "other.zip"] {
            XCTAssertThrowsError(try DistributionPublicationPolicy.validate(clean, names: allowed + [file]))
        }
        object["previousTags"] = ["old-images"]
        let history = try DistributionCatalog.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try DistributionPublicationPolicy.validate(history, names: allowed))
    }

    func testLocalDirectoryRefreshAndValidation() async throws {
        let folder = try temp(), file = folder.appendingPathComponent("local image.tzst")
        let bytes = Data("local-only".utf8)
        try bytes.write(to: file)
        var row: [String: Any] = ["id": "local", "version": "v1", "revision": 1, "title": "Local",
            "coreVersion": "2.13.4-local.666ac4da", "archive": file.lastPathComponent,
            "expandedBytes": 100, "archiveBytes": bytes.count, "archiveSHA256": sha(bytes)]
        let index = folder.appendingPathComponent("images.json")
        func save(_ rows: [[String: Any]]) throws {
            try JSONSerialization.data(withJSONObject: ["schema": 1, "images": rows]).write(to: index)
        }
        try save([row])
        let first = try XCTUnwrap(DistributionLocalImages.read(folder).first)
        XCTAssertEqual(first.image.revision, 1)
        XCTAssertTrue(first.image.parts.isEmpty)
        let cache = folder.appendingPathComponent("no-cache")
        let downloader = DistributionDownload(root: cache) { _ in
            XCTFail("Local directory operations must never fetch")
            throw DistributionError("unexpected network")
        }
        let result = try await downloader.image(first.image, tag: "local", localArchive: first.archive)
        XCTAssertEqual(result, file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        do {
            _ = try await downloader.image(first.image, tag: "old-online-release")
            XCTFail("Online image path must be blocked even for old catalogs")
        } catch { XCTAssertTrue(error.localizedDescription.contains("已停用")) }
        row["revision"] = 2; row["version"] = "v2"; try save([row])
        XCTAssertEqual(try DistributionLocalImages.read(folder).first?.image.revision, 2)
        try save([row, row]); XCTAssertThrowsError(try DistributionLocalImages.read(folder))
        row["archive"] = "../escape.tzst"; try save([row])
        XCTAssertThrowsError(try DistributionLocalImages.read(folder))
        row["archive"] = "missing.tzst"; try save([row])
        XCTAssertThrowsError(try DistributionLocalImages.read(folder))
        row["archive"] = file.lastPathComponent; row["archiveBytes"] = 1; try save([row])
        XCTAssertThrowsError(try DistributionLocalImages.read(folder))
    }
}
