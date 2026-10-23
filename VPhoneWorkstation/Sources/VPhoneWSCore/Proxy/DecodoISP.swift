import Foundation
import Yams

/// ISP Pay/GB uses city-qualified credentials and a static gateway port, not ZIP sessions.
enum DecodoISP {
    static func name(for context: VMCommandContext) -> String {
        DecodoProxy.name(for: context).replacingOccurrences(of: "IP · Decodo ", with: "IP · ISP ")
    }

    static func city(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: " ", with: "_")
        guard value.range(of: #"^[a-z]+(?:_[a-z]+)*$"#, options: .regularExpression) != nil,
              value.count <= 60 else { throw ProxyRouteError("请填写英文城市名，例如 New York") }
        // ISP accepts new_york_city; the generic docs example new_york returns HTTP 400.
        return value == "new_york" ? "new_york_city" : value
    }

    static func nextPort(occupied: Set<Int>, startingAt start: Int = Int.random(in: 10001...63000)) throws -> Int {
        for offset in 0..<53000 {
            let port = 10001 + (start - 10001 + offset) % 53000
            if !occupied.contains(port) { return port }
        }
        throw ProxyRouteError("没有可用的 ISP 静态端口，未修改出口")
    }

    static func endpoint(name: String, template: [String: Any], city input: String, port: Int, location: DecodoLocation? = nil) throws -> VMManualProxy {
        guard template["server"] as? String == "isp.decodo.com",
              template["type"] as? String == "http",
              template["tls"] as? Bool == true,
              let username = template["username"] as? String,
              let password = template["password"] as? String, !password.isEmpty,
              let account = username.range(of: #"^user-[A-Za-z0-9_]+(?=-country-|$)"#, options: .regularExpression),
              (10001...63000).contains(port) else {
            throw ProxyRouteError("未找到可复用的 Decodo ISP HTTPS 账号配置")
        }
        return try VMManualProxy(name: String(name.dropFirst(5)), host: "isp.decodo.com", port: port,
            kind: .http, username: String(username[account]) + (try location?.suffix ?? ("-country-us-city-" + city(input))),
            password: password, tls: true, dialerProxy: template["dialer-proxy"] as? String)
    }
}

extension ClashProxyService {
    public func ispCity(context: VMCommandContext) throws -> String? {
        let snapshot = try snapshot(context: context)
        let source = try String(contentsOf: proxySourceURL(snapshot), encoding: .utf8)
        let node = try ClashProxyDocument(text: source).configuration(named: DecodoISP.name(for: context), key: "prepend")
        return (node?["username"] as? String)?.components(separatedBy: "-city-").dropFirst().first
    }

    public func configureISP(context: VMCommandContext, city: String, expected: VMProxyRoute, location: DecodoLocation? = nil) async throws {
        guard !applying else { throw ProxyRouteError("出口操作正在执行，请稍后重试") }
        let snapshot = try snapshot(context: context)
        let source = try String(contentsOf: proxySourceURL(snapshot), encoding: .utf8)
        let name = DecodoISP.name(for: context)
        let old = try ClashProxyDocument(text: source).configuration(named: name, key: "prepend")
        let root = try Yams.load(yaml: snapshot.runtime) as? [String: Any]
        let nodes = root?["proxies"] as? [[String: Any]] ?? []
        let candidates = nodes.filter { $0["server"] as? String == "isp.decodo.com" }
        guard let template = old ?? candidates.first(where: { $0["name"] as? String == expected.selected }) ?? candidates.first else {
            throw ProxyRouteError("请先配置已购 Decodo ISP 账号；当前 Clash 中没有 ISP 入口")
        }
        let port = try DecodoISP.nextPort(occupied: Set(candidates.compactMap { $0["port"] as? Int }))
        let endpoint = try DecodoISP.endpoint(name: name, template: template, city: city, port: port, location: location)
        try await saveProxy(context: context, proxy: endpoint, expected: expected, replacing: old, activate: true)
    }
}
