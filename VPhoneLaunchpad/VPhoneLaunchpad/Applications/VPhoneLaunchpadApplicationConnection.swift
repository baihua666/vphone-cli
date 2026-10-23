#if VPHONE_CUSTOM_APPLICATION_MANAGEMENT
import Foundation
import VPhoneApplicationManagement

nonisolated enum VPhoneLaunchpadApplicationConnection {
    static func prepareLog(_ url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) {
            guard fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw VPhoneLaunchpadError("无法创建私有连接日志")
            }
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func read(_ url: URL) throws -> VPhoneApplicationConnection {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let mode = attributes[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0 else {
            throw VPhoneLaunchpadError("连接日志不是私有文件，请从新版 Launchpad 重新启动实例。")
        }
        return try VPhoneApplicationConnection(log: String(contentsOf: url, encoding: .utf8))
    }
}
#endif
