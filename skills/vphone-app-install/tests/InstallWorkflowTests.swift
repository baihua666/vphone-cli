import Foundation

func workflowTests() throws {
    let target = InstallConfiguration.Target(name: "one", apiURL: "http://127.0.0.1:18761", tokenFile: "/private/token")
    let valid = InstallConfiguration(ipa: "/private/Instagram.ipa", source: .init(appID: "389801252", bundleID: "com.burbn.instagram", version: "452.0.0"), targets: [target])
    try valid.validate()
    var invalid = [InstallConfiguration]()
    var c = valid; c.targets = []; invalid.append(c)
    c = valid; c.targets.append(target); invalid.append(c)
    c = valid; c.ipa = "relative.ipa"; invalid.append(c)
    c = valid; c.targets[0].apiURL = "http://example.com:18761"; invalid.append(c)
    c = valid; c.targets[0].apiURL = "http://secret@127.0.0.1:18761"; invalid.append(c)
    c = valid; c.source.cookieFile = "relative-cookie"; invalid.append(c)
    c = valid; c.source.chromeProfile = "/Chrome/Default"; invalid.append(c)
    c = valid; c.source.chromeProfile = "relative"; c.source.cookieFile = "/private/cookie"; invalid.append(c)
    c = valid; c.source.chromeProfile = "/Chrome/Default"; c.source.cookieFile = "/private/cookie"; try c.validate()
    for config in invalid {
        var failed = false
        do { try config.validate() } catch { failed = true }
        guard failed else { throw reject("应拒绝的配置被接受") }
    }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("config")
    try Data("test".utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
    var rejected = false
    do { _ = try privateFile(file.path) } catch { rejected = true }
    guard rejected else { throw reject("权限检查失败") }
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    _ = try privateFile(file.path)
}
