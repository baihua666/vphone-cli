import XCTest
import CryptoKit
@testable import VPhoneDistribution

final class DistributionTests: XCTestCase, @unchecked Sendable {
    func temp() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }
    func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    func asset(_ name: String, _ data: Data) -> [String: Any] {
        ["name": name, "size": data.count, "sha256": sha(data)]
    }
    func catalog(_ pieces: [Data] = [Data("one".utf8), Data("two".utf8)]) throws -> DistributionCatalog {
        let whole = pieces.reduce(into: Data()) { $0.append($1) }
        let json: [String: Any] = ["schema": 1, "tag": "launchpad-2.8.0-r1",
            "app": ["baseline": "2.8.0", "revision": 1, "minimumMacOS": 15, "asset": asset("app.dmg", Data([1]))],
            "core": ["version": "2.8.0-local.1234abcd", "asset": asset("core.zip", Data([2]))],
            "images": [["id": "clean", "version": "2026.10.24", "revision": 1, "title": "Clean",
                        "coreVersion": "2.8.0-local.1234abcd", "expandedBytes": 1024,
                        "archiveBytes": whole.count, "archiveSHA256": sha(whole),
                        "parts": pieces.enumerated().map { asset("part\($0.offset)", $0.element) }]]]
        return try DistributionCatalog.decode(JSONSerialization.data(withJSONObject: json))
    }
    func testSigningModeCompatibilityAndUnknownModeRejection() throws {
        let original = try catalog()
        XCTAssertEqual(original.app.signingMode, .notarized)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var app = try XCTUnwrap(json["app"] as? [String: Any])
        app["signing"] = "internalDevelopment"; json["app"] = app
        let internalRelease = try DistributionCatalog.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(internalRelease.app.signingMode, .internalDevelopment)
        XCTAssertEqual(internalRelease.app.revision, original.app.revision)
        XCTAssertThrowsError(try GitHubDistribution.validatedVersions([internalRelease, original]))
        app["signing"] = "unsigned"; json["app"] = app
        XCTAssertThrowsError(try DistributionCatalog.decode(JSONSerialization.data(withJSONObject: json)))
    }
    func testPublisherSplitBoundariesAndRoundTrip()
 throws {
        let folder = try temp(); let input = folder.appendingPathComponent("source.tzst")
        let data = Data("12345678".utf8); try data.write(to: input)
        let result = try DistributionPacking.split(input, prefix: "image", output: folder, partBytes: 4)
        XCTAssertEqual(result.parts.map(\.size), [4, 4])
        XCTAssertEqual(result.bytes, 8); XCTAssertEqual(result.sha256, sha(data))
        var joined = Data()
        for part in result.parts {
            let file = folder.appendingPathComponent(part.name)
            XCTAssertTrue(try DistributionDownload.matches(file, bytes: part.size, digest: part.sha256))
            joined.append(try Data(contentsOf: file))
        }
        XCTAssertEqual(joined, data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("image.part0002").path))
        XCTAssertThrowsError(try DistributionPacking.split(input, prefix: "image", output: folder, partBytes: 4))
        XCTAssertThrowsError(try DistributionPacking.split(input, prefix: "../bad", output: folder, partBytes: 4))
        let uneven = try DistributionPacking.split(input, prefix: "uneven", output: folder, partBytes: 3)
        XCTAssertEqual(uneven.parts.map(\.size), [3, 3, 2])
    }
    func testCompleteArchiveHashIsCheckedAfterValidParts() async throws {
        let folder = try temp(); let value = try catalog()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value.images[0])) as? [String: Any])
        json["archiveSHA256"] = String(repeating: "a", count: 64)
        let image = try JSONDecoder().decode(DistributionImage.self, from: JSONSerialization.data(withJSONObject: json))
        let source = Fixture(folder: folder, data: [Data("one".utf8), Data("two".utf8)])
        let download = DistributionDownload(root: folder.appendingPathComponent("cache")) { try await source.fetch($0) }
        do { _ = try await download.image(image, tag: value.tag); XCTFail("must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("完整镜像")) }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("cache").path)
        XCTAssertFalse(names.contains { $0.hasSuffix(".tzst") || $0.hasSuffix(".assembling") })
        XCTAssertEqual(names.count, 2)
    }
    func testImageOnlyReleaseCanReuseAppRevisionButNotReplaceApp() throws {
        let original = try catalog()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json["tag"] = "image-r2"
        var images = try XCTUnwrap(json["images"] as? [[String: Any]])
        images[0]["revision"] = 2; images[0]["version"] = "2026.10.25"; json["images"] = images
        let mirrorRelease = try DistributionCatalog.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(try GitHubDistribution.validatedVersions([mirrorRelease, original]).first?.tag, "image-r2")
        var app = try XCTUnwrap(json["app"] as? [String: Any])
        app["asset"] = asset("app.dmg", Data([9])); json["app"] = app
        let replaced = try DistributionCatalog.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try GitHubDistribution.validatedVersions([replaced, original]))
    }
    func testCatalogRejectsTraversalInvalidHashesAndMismatchedSize() throws {
        let value = try catalog()
        XCTAssertEqual(value.images.first?.revision, 1)
        XCTAssertThrowsError(try DistributionAsset(name: "../x", size: 1, sha256: String(repeating: "a", count: 64)).validate())
        XCTAssertThrowsError(try DistributionAsset(name: "x", size: 2_147_483_648, sha256: String(repeating: "a", count: 64)).validate())
        XCTAssertThrowsError(try GitHubDistribution.assetURL(tag: "../tag", name: "x"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        var images = try XCTUnwrap(json["images"] as? [[String: Any]])
        images[0]["archiveBytes"] = 1; json["images"] = images
        XCTAssertThrowsError(try DistributionCatalog.decode(JSONSerialization.data(withJSONObject: json)))
        json["schema"] = 9
        XCTAssertThrowsError(try DistributionCatalog.decode(JSONSerialization.data(withJSONObject: json)))
    }
    func testCacheSurvivesFailureAndResumesAtNextChunk() async throws {
        let folder = try temp(); let pieces = [Data("one".utf8), Data("two".utf8)]
        let value = try catalog(pieces); let image = try XCTUnwrap(value.images.first)
        let source = Fixture(folder: folder, data: pieces)
        let download = DistributionDownload(root: folder.appendingPathComponent("cache")) { try await source.fetch($0) }
        await source.failSecond()
        do { _ = try await download.image(image, tag: value.tag); XCTFail("expected failure") } catch {}
        let before = await source.calls
        XCTAssertEqual(before, ["part0", "part1"])
        let output = try await download.image(image, tag: value.tag)
        XCTAssertEqual(try Data(contentsOf: output), pieces[0] + pieces[1])
        let after = await source.calls
        XCTAssertEqual(after, ["part0", "part1", "part1"])
        _ = try await download.image(image, tag: value.tag)
        let cached = await source.calls
        XCTAssertEqual(cached, after)
    }
    func testTamperedChunkIsNotAccepted() async throws {
        let folder = try temp(); let value = try catalog()
        let download = DistributionDownload(root: folder.appendingPathComponent("cache")) { _ in
            let file = folder.appendingPathComponent(UUID().uuidString)
            try Data("bad".utf8).write(to: file); return file
        }
        do { _ = try await download.image(value.images[0], tag: value.tag); XCTFail("expected checksum failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("SHA-256")) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("cache/" + value.images[0].cacheKey + ".tzst").path))
    }
    func testNewIdentityWorkflowNeverOverwritesExistingMachine() async throws {
        let folder = try temp()
        let capture = Commands()
        let output = try await ImageInstallation.prepare(archive: folder.appendingPathComponent("image.tzst"), library: folder, name: "phone", finalize: { ready in
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("phone").path))
            try Data("pinned-core".utf8).write(to: ready.appendingPathComponent("binding-test"))
        }) { args in
            await capture.append(args)
            if args[1] == "clone" {
                let root = try XCTUnwrap(args.last)
                let target = URL(fileURLWithPath: root).appendingPathComponent("phone")
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                try Data("fixture".utf8).write(to: target.appendingPathComponent("config.plist"))
            }
        }
        let commands = await capture.values
        XCTAssertEqual(commands.map { $0[1] }, ["import", "clone"])
        XCTAssertTrue(commands[1].contains("--new-identity"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("binding-test")), Data("pinned-core".utf8))
        do {
            _ = try await ImageInstallation.prepare(archive: folder, library: folder, name: "phone") { _ in XCTFail("must not execute") }
            XCTFail("must refuse existing")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("config.plist")), Data("fixture".utf8))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasPrefix(".distribution-") })
    }
    func testFailedImportCleansOnlyOwnedStaging() async throws {
        let folder = try temp(); let sentinel = folder.appendingPathComponent("user-data")
        try Data([7]).write(to: sentinel)
        do {
            _ = try await ImageInstallation.prepare(archive: folder, library: folder, name: "new") { _ in throw DistributionError("failed") }
            XCTFail("expected failure")
        } catch {}
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["user-data"])
    }
    func testCancellationDoesNotPublishInstance() async throws {
        let folder = try temp()
        do {
            _ = try await ImageInstallation.prepare(archive: folder, library: folder, name: "new") { _ in throw CancellationError() }
            XCTFail("expected cancellation")
        } catch is CancellationError {} catch { XCTFail("wrong error") }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }
    func testImageReceiptSurvivesReopenAndOnlyComparesSameImage() throws {
        let value = try catalog(); let image = value.images[0]
        let receipt = DistributionReceipt(image: image, machinePath: "/isolated-test/phone")
        let reopened = try JSONDecoder().decode(DistributionReceipt.self, from: JSONEncoder().encode(receipt))
        XCTAssertFalse(reopened.updateAvailable(image))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(image)) as? [String: Any])
        json["revision"] = 2
        let newer = try JSONDecoder().decode(DistributionImage.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(reopened.updateAvailable(newer))
        json["id"] = "other"
        let other = try JSONDecoder().decode(DistributionImage.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(reopened.updateAvailable(other))
    }
}
private actor Commands {
    var values: [[String]] = []
    func append(_ value: [String]) { values.append(value) }
}
private actor Fixture {
    let folder: URL; let data: [Data]
    var calls: [String] = []; var fail = false
    init(folder: URL, data: [Data]) { self.folder = folder; self.data = data }
    func failSecond() { fail = true }
    func fetch(_ url: URL) throws -> URL {
        calls.append(url.lastPathComponent)
        let index = Int(url.lastPathComponent.dropFirst(4))!
        if index == 1 && fail { fail = false; throw DistributionError("network interrupted") }
        let file = folder.appendingPathComponent(UUID().uuidString)
        try data[index].write(to: file); return file
    }
}
