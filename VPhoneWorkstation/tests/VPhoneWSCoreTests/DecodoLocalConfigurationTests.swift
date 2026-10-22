import Foundation
import Testing
@testable import VPhoneWSCore

@Test func decodoLocalConfigurationLoadsPrivateFileAndKeepsLeadingZeroZIP() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("decodo.json")
    try Data(#"{"username":"testuser","password":"test-only","zip":"02108"}"#.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    let config = try DecodoLocalConfiguration.load(path: url.path)
    #expect(config?.username == "testuser")
    #expect(config?.password == "test-only")
    #expect(config?.zip == "02108")
    #expect(try DecodoLocalConfiguration.load(path: nil) == nil)
    #expect(throws: (any Error).self) { try DecodoLocalConfiguration.load(path: root.appendingPathComponent("missing").path) }
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    #expect(throws: (any Error).self) { try DecodoLocalConfiguration.load(path: url.path) }
}

@Test func decodoLocalConfigurationRejectsInvalidDataWithoutLeakingContents() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("decodo.json")
    for content in [#"{"username":"testuser","password":"SENSITIVE_TEST""#,
                    #"{"username":"testuser","password":"SENSITIVE_TEST","zip":10001}"#,
                    #"{"username":" ","password":"SENSITIVE_TEST","zip":"10001"}"#,
                    #"{"username":"testuser","password":"SENSITIVE_TEST","zip":"1234"}"#] {
        try Data(content.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        do {
            _ = try DecodoLocalConfiguration.load(path: url.path)
            Issue.record("Invalid configuration was accepted")
        } catch {
            #expect(!error.localizedDescription.contains("SENSITIVE_TEST"))
            #expect(!error.localizedDescription.contains("testuser"))
        }
    }
}
