import XCTest
@testable import VPhoneDistribution

final class ImageVersionTests: XCTestCase {
    private func catalog(tag: String, revision: Int, version: String = "1", core: String = "2.8.0-local.1234abcd") throws -> DistributionCatalog {
        let original = try DistributionTests().catalog()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var images = try XCTUnwrap(json["images"] as? [[String: Any]])
        images[0]["revision"] = revision
        images[0]["version"] = version
        images[0]["coreVersion"] = core
        json["images"] = images
        json["tag"] = tag
        var coreJSON = try XCTUnwrap(json["core"] as? [String: Any])
        coreJSON["version"] = core
        json["core"] = coreJSON
        return try DistributionCatalog.decode(JSONSerialization.data(withJSONObject: json))
    }

    func testAllImageVersionsIndependentOfAppRevisionAndOwningRelease() throws {
        let old = try catalog(tag: "old", revision: 1)
        let latest = try catalog(tag: "latest", revision: 2, version: "2", core: "2.8.0-local.abcdef12")
        let mirror = try catalog(tag: "mirror", revision: 1)
        let catalogs = try GitHubDistribution.validatedVersions([old, latest, mirror])
        let versions = DistributionImageVersion.all(in: catalogs)
        XCTAssertEqual(versions.map(\.id), ["clean:2", "clean:1"])
        XCTAssertEqual(versions.map { $0.catalog.tag }, ["latest", "old"])
        XCTAssertEqual(versions[0].catalog.core.version, versions[0].image.coreVersion)
        XCTAssertEqual(versions[1].catalog.core.version, versions[1].image.coreVersion)
    }

    func testSameImageRevisionCannotSilentlyChangeRequiredCoreOrVersion() throws {
        let original = try catalog(tag: "old", revision: 1)
        for changed in [try catalog(tag: "new", revision: 1, version: "2"),
                        try catalog(tag: "new", revision: 1, core: "2.8.0-local.abcdef12")] {
            XCTAssertThrowsError(try GitHubDistribution.validatedVersions([original, changed]))
        }
    }
}
