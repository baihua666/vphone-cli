import Foundation

public struct DecodoAccount: Codable, Equatable, Sendable {
    public var email = ""
    public var password = ""
    public var apiKey = ""
    public var accessToken = ""
    public var refreshToken = ""
    public init() {}
    enum CodingKeys: String, CodingKey { case email, password, apiKey, accessToken, refreshToken }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        email = try values.decodeIfPresent(String.self, forKey: .email) ?? ""
        password = try values.decodeIfPresent(String.self, forKey: .password) ?? ""
        apiKey = try values.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        accessToken = try values.decodeIfPresent(String.self, forKey: .accessToken) ?? ""
        refreshToken = try values.decodeIfPresent(String.self, forKey: .refreshToken) ?? ""
    }

    public static var userPath: String { NSHomeDirectory() + "/.vphone/decodo-account.json" }
    public static var fallbackPath: String {
        if let path = ProcessInfo.processInfo.environment["VPHONE_DECODO_ACCOUNT"], path.hasPrefix("/") { return path }
        // Local source build fallback; another checkout resolves its own source root at build time.
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".local/decodo-account.json").path
    }
    public static func load() throws -> (account: Self, path: String) {
        let path = FileManager.default.fileExists(atPath: userPath) ? userPath : fallbackPath
        guard FileManager.default.fileExists(atPath: path) else { return (Self(), path) }
        do { return (try JSONDecoder().decode(Self.self, from: Data(contentsOf: URL(fileURLWithPath: path))), path) }
        catch { throw ProxyRouteError("Decodo 账号配置无法读取，请检查 JSON 文件；不会回退到其它账号。") }
    }
    public func save(path: String = Self.userPath) throws {
        guard path.hasPrefix("/") else { throw ProxyRouteError("账号配置路径必须为绝对路径") }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".decodo-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: try encoder.encode(self),
                                            attributes: [.posixPermissions: 0o600]) else { throw ProxyRouteError("无法保存账号配置") }
        guard rename(temporary.path, url.path) == 0 else { throw ProxyRouteError("无法替换账号配置") }
    }
}

/// Public API explicitly excludes ISP; never send an API key to dashboard session endpoints.
public enum DecodoAuthorizationPolicy {
    public static let ispUsesPublicAPIKey = false
    public static let explanation = "官方 Public API Key 不支持 ISP 产品。ISP 地区同步使用账号授权；API Key 已预留保存，不会冒充 ISP 授权。"
}
