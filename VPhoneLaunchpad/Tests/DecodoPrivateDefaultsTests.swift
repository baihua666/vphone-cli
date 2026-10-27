import Foundation

@main struct DecodoPrivateDefaultsTests {
    static func main() throws {
        #if VPHONE_CUSTOM_DECODO_PRIVATE_DEFAULTS
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("Resources")
        let source = resources.appendingPathComponent("DecodoPrivateDefaults")
        let home = root.appendingPathComponent("Home")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try VPhoneLaunchpadDecodoPrivateDefaults.install(resources: resources, home: home)
        precondition(!FileManager.default.fileExists(atPath: home.path), "public installer must do nothing")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        for (name, key) in [("decodo-account.json", "email"), ("decodo-isp.json", "username")] {
            try JSONSerialization.data(withJSONObject: [key: "fixture", "password": "fixture"])
                .write(to: source.appendingPathComponent(name))
        }
        try VPhoneLaunchpadDecodoPrivateDefaults.install(resources: resources, home: home)
        for name in ["decodo-account.json", "decodo-isp.json"] {
            let file = home.appendingPathComponent(".vphone/" + name)
            let actual = try Data(contentsOf: file)
            let expected = try Data(contentsOf: source.appendingPathComponent(name))
            precondition(actual == expected)
            let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as! Int
            precondition(mode == 0o600)
            try Data("existing-user-setting".utf8).write(to: file)
        }
        try VPhoneLaunchpadDecodoPrivateDefaults.install(resources: resources, home: home)
        let preserved = try String(contentsOf: home.appendingPathComponent(".vphone/decodo-account.json"), encoding: .utf8)
        precondition(preserved == "existing-user-setting")
        let anotherHome = root.appendingPathComponent("AnotherHome")
        try Data("{}".utf8).write(to: source.appendingPathComponent("decodo-account.json"))
        do {
            try VPhoneLaunchpadDecodoPrivateDefaults.install(resources: resources, home: anotherHome)
            fatalError("invalid defaults accepted")
        } catch {}
        precondition(!FileManager.default.fileExists(atPath: anotherHome.appendingPathComponent(".vphone/decodo-account.json").path))
        print("PASS: clean Mac seeded, 0600, existing settings preserved, public no-op, invalid defaults rejected")
        #else
        print("PASS: private defaults hook compiled out")
        #endif
    }
}
