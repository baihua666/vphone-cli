import XCTest
@testable import VPhoneDistribution

extension DistributionTests {
    func testMultiBufferSplitHashAndAssembly() async throws {
        let folder = try temp()
        // Cross both the 1 MiB read boundary and an uneven part boundary.
        let bytes = Data((0..<(3 * 1_048_576 + 19)).map { UInt8($0 % 251) })
        let input = folder.appendingPathComponent("source.tzst")
        try bytes.write(to: input)
        let result = try DistributionPacking.split(input, prefix: "large", output: folder, partBytes: 1_572_864)
        XCTAssertEqual(result.parts.map(\.size), [1_572_864, 1_572_864, 19])
        XCTAssertEqual(result.sha256, sha(bytes))
        XCTAssertEqual(try DistributionDownload.digest(input), result.sha256)
        let pieces = try result.parts.map { try Data(contentsOf: folder.appendingPathComponent($0.name)) }
        let value = try catalog(pieces)
        let source = Fixture(folder: folder, data: pieces)
        let download = DistributionDownload(root: folder.appendingPathComponent("cache")) { try await source.fetch($0) }
        let output = try await download.image(value.images[0], tag: "local", localArchive: input)
        XCTAssertEqual(try Data(contentsOf: output), bytes)
    }
}
