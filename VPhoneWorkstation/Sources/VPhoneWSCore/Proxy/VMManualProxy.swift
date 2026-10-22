import Darwin
import Foundation
import Yams

/// A purchased endpoint, not a claim that its public egress is static or exclusive.
public struct VMManualProxy: Sendable {
    public enum Kind: String, CaseIterable, Sendable { case http, socks5 }
    public let name: String
    let host: String
    let port: Int
    let kind: Kind
    let username: String
    let password: String
    let tls: Bool
    let udp: Bool

    public init(name: String, host: String, port: Int, kind: Kind,
                username: String = "", password: String = "", tls: Bool = false, udp: Bool = false) throws {
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let server = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label.count <= 80, !label.contains(","),
              !label.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ProxyRouteError("请填写名称，且不要包含逗号或控制字符")
        }
        var address = in6_addr()
        let validHost = server.contains(":") ? inet_pton(AF_INET6, server, &address) == 1
            : server.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil
        guard validHost, (1...65535).contains(port) else {
            throw ProxyRouteError("请填写不带协议、路径或端口的服务器地址，以及 1–65535 的端口")
        }
        guard kind == .socks5 || !udp else { throw ProxyRouteError("HTTP 代理不支持 UDP") }
        guard username.isEmpty == password.isEmpty else { throw ProxyRouteError("请同时填写用户名和密码；使用 IP 白名单时两项都留空") }
        self.name = "IP · " + label; self.host = server; self.port = port; self.kind = kind
        self.username = username; self.password = password; self.tls = tls; self.udp = udp
    }

    var configuration: [String: Any] {
        var result: [String: Any] = ["name": name, "type": kind.rawValue, "server": host, "port": port,
                                     "tls": tls]
        if !username.isEmpty { result["username"] = username }
        if !password.isEmpty { result["password"] = password }
        if kind == .socks5 { result["udp"] = udp }
        return result
    }
}

/// Insert into a sequence without reserializing subscription content or comments.
struct ClashProxyDocument {
    let text: String

    func adding(_ proxy: VMManualProxy, key: String) throws -> String {
        do {
            guard let root = try Yams.compose(yaml: text), let mapping = root.mapping,
                  mapping.filter({ $0.key.string == key }).count <= 1 else {
                throw ProxyRouteError("代理配置必须是没有重复字段的 YAML 字典")
            }
            let json = String(data: try JSONSerialization.data(withJSONObject: proxy.configuration,
                              options: [.sortedKeys, .withoutEscapingSlashes]), encoding: .utf8)!
            let changed: String
            if root[key] == nil {
                changed = text + (text.hasSuffix("\n") ? "" : "\n") + "\(key):\n- \(json)\n"
            } else {
                guard let sequence = root[key]?.sequence, sequence.anchor == nil, let mark = sequence.mark else {
                    throw ProxyRouteError("代理列表必须是普通 YAML 数组")
                }
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                let offset = lines.prefix(mark.line - 1).reduce(0) { $0 + $1.unicodeScalars.count + 1 } + mark.column - 1
                let scalars = Array(text.unicodeScalars)
                guard offset >= 0, offset < scalars.count else { throw ProxyRouteError("代理列表位置无效") }
                // Yams 6.1.0 reads sequence.style from the end event; inspect the source token instead.
                if scalars[offset] == "[" {
                    changed = String(String.UnicodeScalarView(scalars[...offset])) + json + (sequence.isEmpty ? "" : ", ")
                        + String(String.UnicodeScalarView(scalars[(offset + 1)...]))
                } else if scalars[offset] == "-",
                          lines[mark.line - 1].prefix(mark.column - 1).allSatisfy({ $0 == " " }) {
                    changed = String(String.UnicodeScalarView(scalars[..<offset])) + "- \(json)\n"
                        + String(repeating: " ", count: mark.column - 1) + String(String.UnicodeScalarView(scalars[offset...]))
                } else { throw ProxyRouteError("代理列表样式暂不支持；未修改文件") }
            }
            guard var expected = try Yams.load(yaml: text) as? [String: Any] else {
                throw ProxyRouteError("代理配置必须是 YAML 字典")
            }
            let existing = expected[key] as? [[String: Any]] ?? []
            guard !existing.contains(where: { $0["name"] as? String == proxy.name }) else {
                throw ProxyRouteError("此代理名称已存在，请使用不同名称")
            }
            expected[key] = [proxy.configuration] + existing
            guard let actual = try Yams.load(yaml: changed) as? [String: Any],
                  NSDictionary(dictionary: actual) == NSDictionary(dictionary: expected) else {
                throw ProxyRouteError("代理配置核对失败；未修改文件")
            }
            return changed
        } catch let error as ProxyRouteError { throw error }
        catch { throw ProxyRouteError("无法解析代理配置；请检查 YAML 格式") }
    }
}
