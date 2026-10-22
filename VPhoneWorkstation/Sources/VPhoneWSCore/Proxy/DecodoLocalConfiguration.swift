import Foundation

/// Local form defaults only. Loading never changes the live proxy or VM configuration.
public struct DecodoLocalConfiguration: Decodable, Sendable {
    public let username: String
    public let password: String
    public let zip: String

    public static var defaultPath: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".vphone/decodo.json").path
    }

    public static var resolvedPath: String? {
        if let override = ProcessInfo.processInfo.environment["VPHONE_DECODO_CONFIG"], !override.isEmpty { return override }
        return FileManager.default.fileExists(atPath: defaultPath) ? defaultPath : nil
    }

    public static func load(path: String? = DecodoLocalConfiguration.resolvedPath) throws -> Self? {
        guard let path, !path.isEmpty else { return nil }
        guard path.hasPrefix("/") else { throw ProxyRouteError("Decodo 本机配置路径必须是绝对路径") }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let permissions = attributes[.posixPermissions] as? Int, permissions & 0o077 == 0 else {
                throw ProxyRouteError("Decodo 本机配置必须是仅当前用户可读写的普通文件，请设置权限为 0600")
            }
            guard let size = attributes[.size] as? Int, size <= 65_536 else {
                throw ProxyRouteError("Decodo 本机配置过大")
            }
            let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
            guard !value.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !value.password.isEmpty,
                  value.zip.range(of: #"^[0-9]{5}$"#, options: .regularExpression) != nil else {
                throw ProxyRouteError("Decodo 本机配置需包含非空 username、password，以及五位字符串 zip")
            }
            return value
        } catch let error as ProxyRouteError { throw error }
        catch { throw ProxyRouteError("无法读取 Decodo 本机配置，请检查文件是否存在及 JSON 格式；仍可手动填写") }
    }
}
