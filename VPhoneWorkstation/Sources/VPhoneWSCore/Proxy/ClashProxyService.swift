import Foundation
import Yams

public struct VMProxyRoute: Sendable {
    public let profile: String
    public let process: String
    public let selected: String
    public let choices: [String]
}

/// Clash-specific persistence and routing belong to the workstation, not the VM CLI.
/// One shared actor excludes overlapping transactions across instance views.
public actor ClashProxyService {
    let directory: URL
    let transport: any MihomoTransport
    var applying = false

    public init() {
        directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/io.github.clash-verge-rev.clash-verge-rev")
        transport = SystemMihomoTransport()
    }

    init(directory: URL, transport: any MihomoTransport) {
        self.directory = directory; self.transport = transport
    }

    struct Snapshot {
        let profile: String
        let process: String
        let managedProxyName: String
        let profiles: Data
        let sourceURL: URL
        let runtimeURL: URL
        let source: String
        let runtime: String
        let socket: String
        let secret: String
        var sourceRule: ClashRuleDocument { .init(text: source, key: "prepend", process: process) }
        var runtimeRule: ClashRuleDocument { .init(text: runtime, key: "rules", process: process) }
    }

    func snapshot(context: VMCommandContext) throws -> Snapshot {
        do {
            let process = context.executable.deletingLastPathComponent().appendingPathComponent("vphone-vm").path
            try context.validateProxyIsolation()
            let profiles = try Data(contentsOf: directory.appendingPathComponent("profiles.yaml"))
            let index = try Yams.load(yaml: String(decoding: profiles, as: UTF8.self)) as? [String: Any]
            guard let current = index?["current"] as? String, let items = index?["items"] as? [[String: Any]],
                  let active = items.first(where: { $0["uid"] as? String == current }),
                  let options = active["option"] as? [String: Any], let rulesID = options["rules"] as? String,
                  let rules = items.first(where: { $0["uid"] as? String == rulesID && $0["type"] as? String == "rules" }),
                  let file = rules["file"] as? String, !file.contains("/"), file.hasSuffix(".yaml") else {
                throw ProxyRouteError("当前 Clash 订阅没有可识别的前置规则文件")
            }
            let sourceURL = directory.appendingPathComponent("profiles/" + file)
            let runtimeURL = directory.appendingPathComponent("clash-verge.yaml")
            let runtime = try String(contentsOf: runtimeURL, encoding: .utf8)
            let config = try Yams.load(yaml: runtime) as? [String: Any]
            guard let configuredSocket = config?["external-controller-unix"] as? String, configuredSocket.hasPrefix("/") else {
                throw ProxyRouteError("Clash 未启用本地 Unix 控制接口")
            }
            let serviceSocket = "/var/run/clash-verge-service/users/\(getuid())/verge-mihomo.sock"
            let socket = FileManager.default.fileExists(atPath: serviceSocket) ? serviceSocket : configuredSocket
            return Snapshot(profile: current, process: process, managedProxyName: DecodoProxy.name(for: context), profiles: profiles, sourceURL: sourceURL,
                            runtimeURL: runtimeURL, source: try String(contentsOf: sourceURL, encoding: .utf8),
                            runtime: runtime, socket: socket, secret: config?["secret"] as? String ?? "")
        } catch let error as ProxyRouteError { throw error }
        catch { throw ProxyRouteError("无法读取 Clash 配置或实例绑定；请检查配置格式与文件权限") }
    }

    func request(_ snapshot: Snapshot, _ method: String, _ path: String, _ object: [String: String]? = nil) async throws -> Data {
        try await transport.request(socket: snapshot.socket, secret: snapshot.secret, method: method, path: path,
                                    body: object.map { try JSONSerialization.data(withJSONObject: $0) })
    }

    func validate(_ snapshot: Snapshot) async throws -> VMProxyRoute {
        let configs = try JSONSerialization.jsonObject(with: await request(snapshot, "GET", "/configs")) as? [String: Any]
        guard configs?["mode"] as? String == "rule", (configs?["tun"] as? [String: Any])?["enable"] as? Bool == true,
              configs?["find-process-mode"] as? String == "strict" else {
            throw ProxyRouteError("需要 Clash Rule 模式、TUN 与 strict 进程识别；未自动修改全局设置")
        }
        let selected = try snapshot.sourceRule.target()
        guard try snapshot.runtimeRule.target() == selected else {
            throw ProxyRouteError("订阅规则与运行配置不一致，请先在 Clash Verge 重新激活当前订阅")
        }
        let rules = try await liveRules(snapshot)
        guard rules.filter({ $0.type == "ProcessPath" && $0.payload == snapshot.process }).map(\.proxy) == [selected] else {
            throw ProxyRouteError("Mihomo 生效规则与持久化规则不一致，请刷新 Clash 订阅")
        }
        let data = try await request(snapshot, "GET", "/proxies")
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let proxies = object?["proxies"] as? [String: [String: Any]] ?? [:]
        let choices = proxies.filter { name, value in
            (!DecodoProxy.isManagedName(name) || name == snapshot.managedProxyName) && value["all"] == nil && !["Reject", "RejectDrop", "Pass", "PassRule", "Compatible"].contains(value["type"] as? String ?? "")
                && !name.contains(",") && !name.contains(where: { $0.isNewline })
        }.keys.sorted()
        return VMProxyRoute(profile: snapshot.profile, process: snapshot.process, selected: selected, choices: choices)
    }

    struct Rule: Decodable, Equatable { let type: String; let payload: String; let proxy: String }
    func liveRules(_ snapshot: Snapshot) async throws -> [Rule] {
        struct Response: Decodable { let rules: [Rule] }
        return try JSONDecoder().decode(Response.self, from: await request(snapshot, "GET", "/rules")).rules
    }

    public func route(context: VMCommandContext) async throws -> VMProxyRoute {
        guard !applying else { throw ProxyRouteError("另一台实例正在切换出口，请稍后刷新") }
        return try await validate(snapshot(context: context))
    }

    public func apply(context: VMCommandContext, target: String, expected: VMProxyRoute) async throws {
        guard !applying else { throw ProxyRouteError("另一台实例正在切换出口，请稍后重试") }
        applying = true
        defer { applying = false }
        let snapshot = try snapshot(context: context)
        let route = try await validate(snapshot)
        guard route.profile == expected.profile, route.process == expected.process, route.selected == expected.selected else {
            throw ProxyRouteError("订阅或实例出口已改变，请刷新后重试")
        }
        guard route.choices.contains(target) else { throw ProxyRouteError("所选节点已不在当前订阅中") }
        let previousRules = try await liveRules(snapshot)
        let source = try snapshot.sourceRule.replacing(target: target)
        let runtime = try snapshot.runtimeRule.replacing(target: target)
        guard try Data(contentsOf: directory.appendingPathComponent("profiles.yaml")) == snapshot.profiles,
              try String(contentsOf: snapshot.sourceURL, encoding: .utf8) == snapshot.source,
              try String(contentsOf: snapshot.runtimeURL, encoding: .utf8) == snapshot.runtime else {
            throw ProxyRouteError("Clash 配置被其它操作更新，请刷新后重试")
        }
        var phase = "写入规则"
        do {
            try Self.writeProxyFile(source, to: snapshot.sourceURL)
            try Self.writeProxyFile(runtime, to: snapshot.runtimeURL)
            phase = "重载 Mihomo"
            _ = try await request(snapshot, "PUT", "/configs?force=false", ["payload": runtime])
            phase = "核对生效规则"
            let updated = try await liveRules(snapshot)
            let expectedRules = previousRules.map { rule in
                rule.type == "ProcessPath" && rule.payload == snapshot.process
                    ? Rule(type: rule.type, payload: rule.payload, proxy: target) : rule
            }
            guard updated == expectedRules else { throw ProxyRouteError("生效规则验证不一致") }
            phase = "核对持久化配置"
            guard try Data(contentsOf: directory.appendingPathComponent("profiles.yaml")) == snapshot.profiles,
                  try String(contentsOf: snapshot.sourceURL, encoding: .utf8) == source,
                  try String(contentsOf: snapshot.runtimeURL, encoding: .utf8) == runtime else {
                throw ProxyRouteError("切换期间 Clash 配置发生变化")
            }
        } catch {
            // Restore only files still equal to our write; never overwrite a concurrent external edit.
            let unchangedSource = (try? String(contentsOf: snapshot.sourceURL, encoding: .utf8)) == source
            let unchangedRuntime = (try? String(contentsOf: snapshot.runtimeURL, encoding: .utf8)) == runtime
            if unchangedSource { try? Self.writeProxyFile(snapshot.source, to: snapshot.sourceURL) }
            if unchangedRuntime { try? Self.writeProxyFile(snapshot.runtime, to: snapshot.runtimeURL) }
            if unchangedRuntime { _ = try? await request(snapshot, "PUT", "/configs?force=false", ["payload": snapshot.runtime]) }
            throw ProxyRouteError("出口切换失败（\(phase)），已尝试恢复未被其它操作改动的规则；请刷新核对状态")
        }
        try await disconnect(snapshot)
    }

    func disconnect(_ snapshot: Snapshot) async throws {
        // Keep other VMs and host traffic connected. Existing target flows otherwise keep their old route.
        struct Connections: Decodable {
            struct Connection: Decodable { let id: String; let metadata: Metadata }
            struct Metadata: Decodable { let processPath: String? }
            let connections: [Connection]?
        }
        let connections = try JSONDecoder().decode(Connections.self, from: await request(snapshot, "GET", "/connections"))
        for connection in connections.connections ?? [] where connection.metadata.processPath == snapshot.process {
            guard UUID(uuidString: connection.id) != nil else { continue }
            _ = try await request(snapshot, "DELETE", "/connections/" + connection.id)
        }
    }
}
