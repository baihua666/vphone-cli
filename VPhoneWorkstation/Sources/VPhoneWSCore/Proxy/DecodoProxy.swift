import CryptoKit
import Foundation

public struct DecodoSession: Sendable, Equatable {
    public let zip: String
    public let id: String
}

/// Supplier parameters remain in the existing private Clash node, outside the VM manifest.
struct DecodoProxy {
    static let prefix = "IP · Decodo "
    let proxy: VMManualProxy
    let session: DecodoSession

    static func isManagedName(_ name: String) -> Bool {
        guard name.hasPrefix(prefix) else { return false }
        let identity = name.dropFirst(prefix.count)
        return identity.count == 64 && identity.allSatisfy { "0123456789abcdef".contains($0) }
    }

    static func name(for context: VMCommandContext) -> String {
        let identity = context.directory.resolvingSymlinksInPath().path
        return prefix + SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    init(context: VMCommandContext, username: String, password: String, zip: String) throws {
        let input = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = input.hasPrefix("user-") ? String(input.dropFirst(5)) : input
        let zip = zip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard zip.range(of: #"^[0-9]{5}$"#, options: .regularExpression) != nil else {
            throw ProxyRouteError("美国 ZIP 必须是五位数字，例如 02108")
        }
        guard account.range(of: #"^[A-Za-z0-9_]+$"#, options: .regularExpression) != nil,
              !password.isEmpty else {
            throw ProxyRouteError("请输入 Decodo 原始代理用户名和密码；用户名不含地区或会话参数")
        }
        session = DecodoSession(zip: zip, id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
        proxy = try VMManualProxy(name: String(Self.name(for: context).dropFirst(5)), host: "gate.decodo.com", port: 7000,
            kind: .http, username: "user-\(account)-country-us-zip-\(zip)-session_iplock-\(session.id)-sessionduration-5",
            password: password, tls: true)
    }

    static func decode(_ node: [String: Any]) throws -> (username: String, password: String, session: DecodoSession) {
        guard node["server"] as? String == "gate.decodo.com", node["port"] as? Int == 7000,
              node["type"] as? String == "http", node["tls"] as? Bool == true,
              let password = node["password"] as? String, !password.isEmpty,
              let username = node["username"] as? String else { throw invalid() }
        let regex = try NSRegularExpression(pattern: #"^user-([A-Za-z0-9_]+)-country-us-zip-([0-9]{5})-session_iplock-([a-f0-9]{32})-sessionduration-5$"#)
        guard let match = regex.firstMatch(in: username, range: NSRange(username.startIndex..., in: username)) else { throw invalid() }
        let string = username as NSString
        return (string.substring(with: match.range(at: 1)), password,
                DecodoSession(zip: string.substring(with: match.range(at: 2)), id: string.substring(with: match.range(at: 3))))
    }

    private static func invalid() -> ProxyRouteError {
        ProxyRouteError("本实例 Decodo 配置已被修改或不完整，请核对代理扩展后重新配置")
    }
}
