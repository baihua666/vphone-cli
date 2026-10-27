import Foundation

#if VPHONE_CUSTOM_DECODO_PRIVATE_DEFAULTS
/// Private installers seed the existing local configuration once; normal
/// public installers have no such resource and retain the original path.
enum VPhoneLaunchpadDecodoPrivateDefaults {
    static func install(resources: URL? = Bundle.main.resourceURL,
                        home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        guard let resources else { return }
        let source = resources.appendingPathComponent("DecodoPrivateDefaults")
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let directory = home.appendingPathComponent(".vphone")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        for (name, userKey) in [("decodo-account.json", "email"), ("decodo-isp.json", "username")] {
            let destination = directory.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            let data = try Data(contentsOf: source.appendingPathComponent(name))
            guard data.count < 65_536,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: String],
                  object[userKey]?.isEmpty == false, object["password"]?.isEmpty == false else {
                throw NSError(domain: "DecodoPrivateDefaults", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "内置 Decodo 配置不完整：" + name])
            }
            // A private temporary inode plus an exclusive link preserves both
            // mode 0600 and settings created concurrently by another process.
            let temporary = directory.appendingPathComponent(".decodo-seed-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard FileManager.default.createFile(atPath: temporary.path, contents: data,
                                                 attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            do { try FileManager.default.linkItem(at: temporary, to: destination) }
            catch {
                guard FileManager.default.fileExists(atPath: destination.path) else { throw error }
            }
        }
    }
}
#endif
