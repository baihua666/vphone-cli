import Foundation
import Observation

@Observable @MainActor
public final class NativeDecodoController {
    private static var pendingPorts = Set<Int>()
    public var credentialsPath = ProcessInfo.processInfo.environment["VPHONE_DECODO_ISP_CONFIG"]
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".vphone/decodo-isp.json").path
    public var isp = true
    public var city = "new_york_city"
    public var zip = "10001"
    public var interface = "wifi"
    public var device = "en1"
    public private(set) var supported = false
    public private(set) var enabled = false
    public private(set) var busy = false
    public private(set) var message = "尚未检测核心能力"
    public private(set) var endpoint = "尚未应用"
    public private(set) var location: IPLocation?
    public private(set) var guestIP: String?
    private let client: VPhoneCLIClient
    private let name: String

    public init(client: VPhoneCLIClient, name: String) { self.client = client; self.name = name }

    public func configuredLocation(in locations: [DecodoLocation]) -> DecodoLocation? {
        guard let context = try? client.context(name: name),
              let config = try? NativeDecodoService.savedConfiguration(directory: context.directory),
              config.host == "isp.decodo.com" else { return nil }
        let suffix = config.username.range(of: "-country-").map { String(config.username[$0.lowerBound...]) } ?? ""
        return locations.first { $0.suffix == suffix }
    }

    public func refresh() async {
        do {
            let status = try await client.networkStatus(name: name)
            supported = status.nativeProxySupported == true; enabled = status.nativeProxyEnabled == true
            endpoint = status.nativeProxyEndpoint ?? "尚未应用"
            if let context = try? client.context(name: name),
               let config = try? NativeDecodoService.savedConfiguration(directory: context.directory) {
                isp = config.host == "isp.decodo.com"
                interface = config.interface
            }
            message = supported ? "当前核心支持原生代理；选择选项不会立即切换。" : "当前核心尚不支持原生代理。保留 Clash，使用独立测试实例验证新版核心。"
        } catch { supported = false; message = "无法读取运行核心能力：" + error.localizedDescription }
    }

    /// Tests a newly requested endpoint without changing any VM or Clash configuration.
    public func testDirect(location: DecodoLocation? = nil) async { await execute(apply: false, target: location) }
    public func rotate(location: DecodoLocation? = nil) async { await execute(apply: true, target: location) }

    private func execute(apply: Bool, target: DecodoLocation?) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        location = nil; guestIP = nil
        var applied = false
        var reservedPort: Int?
        defer { if let reservedPort { Self.pendingPorts.remove(reservedPort) } }
        do {
            let context = try client.context(name: name)
            if apply {
                let status = try await client.networkStatus(name: name)
                guard status.nativeProxySupported == true else { throw ProxyRouteError("此运行核心不支持原生代理，未修改任何出口") }
            }
            guard device.range(of: #"^en[0-9]+$"#, options: .regularExpression) != nil else { throw ProxyRouteError("请指定物理网卡，例如 en1") }
            try NativeDecodoService.validateDevice(device, type: interface)
            let credentials = try NativeDecodoService.credentials(path: credentialsPath)
            var config = try NativeDecodoService.configuration(context: context, credentials: credentials,
                isp: isp, city: city, zip: zip, interface: interface, location: target,
                occupied: try NativeDecodoService.occupiedPorts(context: context).union(Self.pendingPorts))
            if isp { reservedPort = config.port; Self.pendingPorts.insert(config.port) }
            message = "正在直连 Decodo 检测新入口…"
            config.address = try await NativeDecodoService.resolve(host: config.host, device: device)
            location = try await NativeDecodoService.probe(config, device: device)
            endpoint = "\(config.host):\(config.port)"
            guard apply else { message = "独立直连检测成功；尚未应用到虚拟机。"; return }
            guard try client.context(name: name).executable == context.executable else { throw ProxyRouteError("实例核心绑定发生变化，未应用") }
            let file = try NativeDecodoService.save(config, context: context)
            try await client.setNativeProxy(name: name, path: file.path)
            applied = true; enabled = true
            let status = try await client.networkStatus(name: name, probe: true)
            guestIP = status.egress?.ip
            if guestIP == location?.ip { message = "已应用原生出口，虚拟机实测 IP 与 Decodo 一致。" }
            else { message = "已应用；虚拟机检测尚未确认一致：\(status.egressError ?? guestIP ?? "未返回结果")。可明确切回 Clash。" }
            if let target, target.kind == .city,
               DecodoLocation.token(location?.city ?? "") != DecodoLocation.token(target.city) {
                message += " 实测城市与所选城市不同，不能视为地区定位通过。"
            }
        } catch {
            // Keep the private configuration after an uncertain IPC result: the VM may have applied it.
            message = (applied ? "原生出口已应用，但检测失败：" : "操作失败：") + error.localizedDescription
        }
    }

    public func restoreClash() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            try await client.setNativeProxy(name: name, path: nil)
            enabled = false; guestIP = nil; location = nil
            message = "已恢复宿主机网络路径；沿用现有 Clash 规则。"
        } catch { message = error.localizedDescription }
    }

    public func detectGuest() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let status = try await client.networkStatus(name: name, probe: true)
            guestIP = status.egress?.ip
            message = guestIP == nil ? (status.egressError ?? "未返回 IP") : "检测完成，未修改代理。"
        } catch { message = error.localizedDescription }
    }
}
