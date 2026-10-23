import XCTest
@testable import VPhoneApplicationManagement
final class ApplicationTests: XCTestCase {
    func testDownloadRequiresPrivateSessionAndSafeDestination() throws {
        let args = ["--app-id", "389801252", "--bundle-id", "com.test.app", "--version", "1.0"]
        XCTAssertFalse(try Options(args).download)
        XCTAssertThrowsError(try Options(args + ["--download"]))
        XCTAssertThrowsError(try Options(args + ["--country", "../"]))
        XCTAssertThrowsError(try Options(args + ["--output", "relative.ipa"]))
        XCTAssertThrowsError(try Options(args + ["--timeout", "nan"]))
    }
    func testPerLaunchEndpointAndCredentialValidation() throws {
        let token = String(repeating: "a", count: 64)
        let log = "[api] HTTP/WebSocket API: http://127.0.0.1:1234\n[api] token: \(token)\n"
        XCTAssertEqual(try VPhoneApplicationConnection(log: log).baseURL.port, 1234)
        XCTAssertThrowsError(try VPhoneApplicationConnection(log: ""))
        XCTAssertThrowsError(try VPhoneApplicationConnection(log: log.replacingOccurrences(of: "127.0.0.1", with: "example.com")))
        XCTAssertThrowsError(try VPhoneApplicationConnection(log: log + "[api] HTTP/WebSocket API: http://127.0.0.1:5678\n"))
        XCTAssertEqual(try VPhoneApplicationConnection(log: log + log.replacingOccurrences(of: "1234", with: "5678")).baseURL.port, 5678)
    }
    func testInvalidPackageAndMissingDirectory() {
        XCTAssertThrowsError(try VPhoneApplicationLibrary.inspect(URL(fileURLWithPath: "/tmp/missing.ipa")))
        let result = VPhoneApplicationLibrary.scan([URL(fileURLWithPath: "/nonexistent/ipa-library")])
        XCTAssertTrue(result.apps.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
    }
    @MainActor func testRealArchiveMetadataDeduplicationAndCorruption() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let payload = root.appendingPathComponent("Payload/Example.app")
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        let plist: [String: String] = ["CFBundleIdentifier": "org.example.fixture", "CFBundleDisplayName": "Example", "CFBundleShortVersionString": "2.1", "CFBundleVersion": "2103"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            .write(to: payload.appendingPathComponent("Info.plist"))
        let ipa = root.appendingPathComponent("Example.ipa")
        let zip = Process(); zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = root; zip.arguments = ["-qr", ipa.path, "Payload"]
        try zip.run(); zip.waitUntilExit(); XCTAssertEqual(zip.terminationStatus, 0)
        try VPhoneApplicationLibrary.validate(ipa)
        let app = try VPhoneApplicationLibrary.inspect(ipa)
        XCTAssertEqual(app.bundleID, "org.example.fixture"); XCTAssertEqual(app.version, "2.1")
        XCTAssertEqual(app.build, "2103")
        XCTAssertEqual(VPhoneApplicationLibrary.scan([root, root]).apps.count, 1)
        var requests: [String] = []
        var uploadedPath = ""
        let installed = try await VPhoneApplicationInstallation.install(url: ipa, bundleID: app.bundleID, upload: { url, path in
            XCTAssertEqual(url, ipa)
            uploadedPath = path
            requests.append("upload")
        }) { request, timeout in
            XCTAssertEqual(request["t"] as? String, "rpc")
            let method = request["method"] as! String
            requests.append(method)
            if method == "apps.install" {
                XCTAssertEqual((request["params"] as? [String: String])?["path"], uploadedPath)
                XCTAssertEqual(timeout, 660)
            }
            return ["ok": true, "result": ["apps": [["bundle_id": app.bundleID]]]]
        }
        XCTAssertEqual(installed, [app.bundleID])
        XCTAssertEqual(requests, ["apps.list", "files.mkdir", "upload", "apps.install", "files.remove", "apps.list"])
        requests = []
        do {
            _ = try await VPhoneApplicationInstallation.install(url: ipa, bundleID: app.bundleID, upload: { _, _ in
                XCTFail("Disconnected target must not upload")
            }) { _, _ in throw URLError(.cannotConnectToHost) }
            XCTFail("Disconnected target must fail")
        } catch {}
        do {
            _ = try await VPhoneApplicationInstallation.install(url: ipa, bundleID: app.bundleID, upload: { _, _ in }) { request, _ in
                let method = request["method"] as! String; requests.append(method)
                if method == "apps.install" { throw URLError(.timedOut) }
                return ["ok": true, "result": [:]]
            }
            XCTFail("Timeout must not report success")
        } catch {
            XCTAssertEqual(requests, ["apps.list", "files.mkdir", "apps.install"])
        }
        requests = []
        do {
            _ = try await VPhoneApplicationInstallation.install(url: ipa, bundleID: app.bundleID, upload: { _, _ in
                throw URLError(.networkConnectionLost)
            }) { request, _ in
                requests.append(request["method"] as! String)
                return ["ok": true, "result": [:]]
            }
            XCTFail("Failed upload must not install")
        } catch { XCTAssertEqual(requests, ["apps.list", "files.mkdir", "files.remove"]) }
        do {
            _ = try await VPhoneApplicationInstallation.install(url: ipa, bundleID: app.bundleID, upload: { _, _ in }) { request, _ in
                if request["method"] as? String == "apps.install" {
                    return ["ok": false, "error": "guest connection closed"]
                }
                return ["ok": true, "result": [:]]
            }
            XCTFail("A rejected install must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("guest connection closed"))
            XCTAssertTrue(error.localizedDescription.contains("保留的临时包"))
        }
        try Data("invalid".utf8).write(to: ipa)

        XCTAssertThrowsError(try VPhoneApplicationLibrary.validate(ipa))
    }

}
