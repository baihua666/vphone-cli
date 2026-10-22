import Foundation
import Yams

extension ClashProxyService {
    public func decodoSession(context: VMCommandContext) throws -> DecodoSession? {
        guard !applying else { throw ProxyRouteError("出口操作正在执行，请稍后刷新") }
        guard let node = try decodoConfiguration(context: context) else { return nil }
        return try DecodoProxy.decode(node).session
    }

    public func configureDecodo(context: VMCommandContext, username: String, password: String,
                                zip: String, expected: VMProxyRoute) async throws -> DecodoSession {
        let old = try decodoConfiguration(context: context)
        if let old { _ = try DecodoProxy.decode(old) }
        let endpoint = try DecodoProxy(context: context, username: username, password: password, zip: zip)
        try await saveProxy(context: context, proxy: endpoint.proxy, expected: expected, replacing: old, activate: true)
        return endpoint.session
    }

    public func rotateDecodo(context: VMCommandContext, zip: String, expected: VMProxyRoute) async throws -> DecodoSession {
        guard let old = try decodoConfiguration(context: context) else { throw ProxyRouteError("请先配置此实例的 Decodo 账号") }
        let credentials = try DecodoProxy.decode(old)
        let endpoint = try DecodoProxy(context: context, username: credentials.username, password: credentials.password, zip: zip)
        try await saveProxy(context: context, proxy: endpoint.proxy, expected: expected, replacing: old, activate: true)
        return endpoint.session
    }

    private func decodoConfiguration(context: VMCommandContext) throws -> [String: Any]? {
        do {
            let snapshot = try snapshot(context: context)
            let source = try String(contentsOf: proxySourceURL(snapshot), encoding: .utf8)
            return try ClashProxyDocument(text: source).configuration(named: DecodoProxy.name(for: context), key: "prepend")
        } catch let error as ProxyRouteError { throw error }
        catch { throw ProxyRouteError("无法读取 Decodo 配置") }
    }

    func proxySourceURL(_ snapshot: Snapshot) throws -> URL {
        let index = try Yams.load(yaml: String(decoding: snapshot.profiles, as: UTF8.self)) as? [String: Any]
        let items = index?["items"] as? [[String: Any]] ?? []
        let options = items.first(where: { $0["uid"] as? String == snapshot.profile })?["option"] as? [String: Any]
        guard let id = options?["proxies"] as? String,
              let file = items.first(where: { $0["uid"] as? String == id && $0["type"] as? String == "proxies" })?["file"] as? String,
              !file.contains("/"), file.hasSuffix(".yaml") else {
            throw ProxyRouteError("当前订阅没有绑定代理扩展文件；请先在 Clash Verge 启用代理扩展")
        }
        let url = directory.appendingPathComponent("profiles/" + file)
        guard url.resolvingSymlinksInPath() != snapshot.sourceURL.resolvingSymlinksInPath(),
              url.resolvingSymlinksInPath() != snapshot.runtimeURL.resolvingSymlinksInPath() else {
            throw ProxyRouteError("代理扩展不能与规则文件共用路径")
        }
        return url
    }
}
