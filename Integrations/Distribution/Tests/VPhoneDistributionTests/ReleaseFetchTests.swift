import XCTest
@testable import VPhoneDistribution

final class ReleaseFetchTests: XCTestCase, @unchecked Sendable {
    func data(tag: String = "release-r1", previous: [String] = []) throws -> Data {
        let original = try DistributionTests().catalog()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json["tag"] = tag; json["previousTags"] = previous
        return try JSONSerialization.data(withJSONObject: json, options: .sortedKeys)
    }
    func testLatestAndHistoryNeverUseRESTAPI() async throws {
        let latest = try data(tag: "release-r2", previous: ["release-r1"])
        let old = try data()
        let catalogs = try await GitHubDistribution.fetch { url in
            XCTAssertEqual(url.host, "github.com")
            if url.path.contains("/release-r1/") { return (old, 200) }
            return (latest, 200)
        }
        XCTAssertEqual(catalogs.map(\.tag), ["release-r2", "release-r1"])
    }
    func testNoReleaseAndNetworkFailuresDiffer() async throws {
        let empty = try await GitHubDistribution.fetch { _ in (Data(), 404) }
        XCTAssertTrue(empty.isEmpty)
        for status in [403, 429, 500] {
            do {
                _ = try await GitHubDistribution.fetch { _ in (Data(), status) }
                XCTFail("HTTP errors must not report up to date")
            } catch { XCTAssertTrue(error.localizedDescription.contains("HTTP \(status)")) }
        }
    }
    func testTagMismatchAndInvalidHistoryAreRejected() async throws {
        let latest = try data()
        let wrong = try data(tag: "other")
        do {
            _ = try await GitHubDistribution.fetch { url in
                (url == GitHubDistribution.latestCatalogURL ? latest : wrong, 200)
            }
            XCTFail("mismatched tag")
        } catch { XCTAssertTrue(error.localizedDescription.contains("tag")) }
        for history in [["../escape"], ["release-r1"], ["old", "old"]] {
            XCTAssertThrowsError(try DistributionCatalog.decode(data(previous: history)))
        }
    }
}
