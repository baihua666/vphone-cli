import Darwin
import Foundation
import Yams

extension ClashProxyService {
    /// Register an endpoint without changing any VM's chosen route.
    public func addProxy(context: VMCommandContext, proxy: VMManualProxy, expected: VMProxyRoute) async throws {
        try await saveProxy(context: context, proxy: proxy, expected: expected, replacing: nil, activate: false)
    }

    func saveProxy(context: VMCommandContext, proxy: VMManualProxy, expected: VMProxyRoute,
                   replacing old: [String: Any]?, activate: Bool) async throws {
        guard !applying else { throw ProxyRouteError("另一项出口操作正在执行，请稍后重试") }
        applying = true
        defer { applying = false }
        do {
            let snapshot = try snapshot(context: context)
            let route = try await validate(snapshot)
            guard route.profile == expected.profile, route.process == expected.process, route.selected == expected.selected else {
                throw ProxyRouteError("订阅或实例出口已改变，请刷新后重试")
            }
            let proxies = try JSONSerialization.jsonObject(with: await request(snapshot, "GET", "/proxies")) as? [String: Any]
            guard old != nil || (proxies?["proxies"] as? [String: Any])?[proxy.name] == nil else {
                throw ProxyRouteError("此代理名称已存在，请使用不同名称")
            }
            let selections = try Self.selectorSelections(proxies)
            let runtime = try Yams.load(yaml: snapshot.runtime) as? [String: Any]
            // Mihomo 1.19.32 defaults this option to true; explicit false cannot retain selection across regeneration.
            guard (runtime?["profile"] as? [String: Any])?["store-selected"] as? Bool != false else {
                throw ProxyRouteError("请先在 Clash Verge 启用保存策略组选择（profile.store-selected）")
            }
            let groups = runtime?["proxy-groups"] as? [[String: Any]] ?? []
            guard !groups.contains(where: {
                $0["type"] as? String != "select"
                    && ($0["include-all"] as? Bool == true || $0["include-all-proxies"] as? Bool == true)
            }) else {
                throw ProxyRouteError("自动策略组会收集新增或更新的节点；请先关闭该组的 include-all / include-all-proxies 后重试")
            }
            let sourceURL = try proxySourceURL(snapshot)
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            let changedSource: String
            var changedRuntime: String
            if let old {
                changedSource = try ClashProxyDocument(text: source).replacing(proxy, key: "prepend", expected: old)
                changedRuntime = try ClashProxyDocument(text: snapshot.runtime).replacing(proxy, key: "proxies", expected: old)
            } else {
                changedSource = try ClashProxyDocument(text: source).adding(proxy, key: "prepend")
                changedRuntime = try ClashProxyDocument(text: snapshot.runtime).adding(proxy, key: "proxies")
            }
            let changedRules = activate ? try snapshot.sourceRule.replacing(target: proxy.name) : snapshot.source
            if activate {
                changedRuntime = try ClashRuleDocument(text: changedRuntime, key: "rules", process: snapshot.process).replacing(target: proxy.name)
            }
            let previousRules = try await liveRules(snapshot)
            if old != nil {
                let nodes = proxies?["proxies"] as? [String: [String: Any]] ?? [:]
                guard !nodes.values.contains(where: {
                    $0["now"] as? String == proxy.name
                        || ($0["type"] as? String != "Selector" && ($0["all"] as? [String])?.contains(proxy.name) == true)
                }),
                      !previousRules.contains(where: { $0.proxy == proxy.name && !($0.type == "ProcessPath" && $0.payload == snapshot.process) }) else {
                    throw ProxyRouteError("此 Decodo 节点正被其它规则或策略组使用，请先解除共享")
                }
            }
            let expectedRules = previousRules.map { rule in
                activate && rule.type == "ProcessPath" && rule.payload == snapshot.process
                    ? Rule(type: rule.type, payload: rule.payload, proxy: proxy.name) : rule
            }
            func filesUnchanged() throws -> Bool {
                try Data(contentsOf: directory.appendingPathComponent("profiles.yaml")) == snapshot.profiles
                    && String(contentsOf: sourceURL, encoding: .utf8) == source
                    && String(contentsOf: snapshot.sourceURL, encoding: .utf8) == snapshot.source
                    && String(contentsOf: snapshot.runtimeURL, encoding: .utf8) == snapshot.runtime
            }
            guard try filesUnchanged() else { throw ProxyRouteError("Clash 配置已改变，请刷新后重试") }
            // Verge 2.5.8 prepends imported nodes to its first selector on regeneration. Cache even
            // never-explicitly-selected defaults so a later regeneration cannot silently switch host traffic.
            for (name, selected) in selections.sorted(by: { $0.key < $1.key }) {
                guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
                    throw ProxyRouteError("无法保存策略组当前选择")
                }
                _ = try await request(snapshot, "PUT", "/proxies/" + encoded, ["name": selected])
            }
            guard try await currentSelections(snapshot) == selections, try filesUnchanged() else {
                throw ProxyRouteError("策略组或配置已改变，请刷新后重试")
            }
            do {
                try Self.writeProxyFile(changedSource, to: sourceURL)
                if activate { try Self.writeProxyFile(changedRules, to: snapshot.sourceURL) }
                try Self.writeProxyFile(changedRuntime, to: snapshot.runtimeURL)
                _ = try await request(snapshot, "PUT", "/configs?force=false", ["payload": changedRuntime])
                guard try await liveRules(snapshot) == expectedRules,
                      try await currentSelections(snapshot) == selections,
                      try Data(contentsOf: directory.appendingPathComponent("profiles.yaml")) == snapshot.profiles,
                      try String(contentsOf: sourceURL, encoding: .utf8) == changedSource,
                      try String(contentsOf: snapshot.sourceURL, encoding: .utf8) == changedRules,
                      try String(contentsOf: snapshot.runtimeURL, encoding: .utf8) == changedRuntime else {
                    throw ProxyRouteError("代理保存与生效核对失败")
                }
                let updated = try await validate(self.snapshot(context: context))
                guard updated.choices.contains(proxy.name) else { throw ProxyRouteError("Mihomo 未加载新增代理") }
            } catch {
                let ownSource = (try? String(contentsOf: sourceURL, encoding: .utf8)) == changedSource
                let ownRuntime = (try? String(contentsOf: snapshot.runtimeURL, encoding: .utf8)) == changedRuntime
                if activate, (try? String(contentsOf: snapshot.sourceURL, encoding: .utf8)) == changedRules { try? Self.writeProxyFile(snapshot.source, to: snapshot.sourceURL) }
                if ownSource { try? Self.writeProxyFile(source, to: sourceURL) }
                if ownRuntime { try? Self.writeProxyFile(snapshot.runtime, to: snapshot.runtimeURL) }
                if ownRuntime, (try? Data(contentsOf: directory.appendingPathComponent("profiles.yaml"))) == snapshot.profiles {
                    _ = try? await request(snapshot, "PUT", "/configs?force=false", ["payload": snapshot.runtime])
                }
                throw ProxyRouteError("代理更新失败，已尝试恢复未被其它操作改动的配置；请刷新核对状态")
            }
            if activate {
                do { try await disconnect(snapshot) }
                catch { throw ProxyRouteError("会话和规则已保存生效，但断开本实例旧连接失败；旧连接可能仍用原 IP，请刷新并重试换新 IP") }
            }
        } catch let error as ProxyRouteError { throw error }
        catch { throw ProxyRouteError("无法保存代理；请检查订阅文件和本地代理服务") }
    }

    private func currentSelections(_ snapshot: Snapshot) async throws -> [String: String] {
        let response = try JSONSerialization.jsonObject(with: await request(snapshot, "GET", "/proxies")) as? [String: Any]
        return try Self.selectorSelections(response)
    }

    private static func selectorSelections(_ response: [String: Any]?) throws -> [String: String] {
        guard let nodes = response?["proxies"] as? [String: [String: Any]] else {
            throw ProxyRouteError("无法读取策略组当前选择")
        }
        var result: [String: String] = [:]
        for (name, node) in nodes where node["type"] as? String == "Selector" {
            guard let selected = node["now"] as? String, !selected.isEmpty,
                  (node["all"] as? [String])?.contains(selected) == true else {
                throw ProxyRouteError("无法核对策略组当前选择")
            }
            result[name] = selected
        }
        return result
    }

    // Credentials are needed by the external core; create the replacement with 0600 before writing any bytes.
    static func writeProxyFile(_ text: String, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".vphone-proxy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
        guard descriptor >= 0 else { throw ProxyRouteError("无法保存代理配置") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
        guard rename(temporary.path, url.path) == 0 else { throw ProxyRouteError("无法保存代理配置") }
    }
}
