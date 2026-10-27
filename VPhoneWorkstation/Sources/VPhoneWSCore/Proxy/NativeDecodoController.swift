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
    #if VPHONE_CUSTOM_NATIVE_INTERFACE_SELECTION
    public var device = ""
    #else
    public var device = "en1"
    #endif
    public private(set) var configurationMessage: String?
    public private(set) var supported = false
    public private(set) var enabled = false
    public private(set) var busy = false
    public private(set) var message = "尚未检测核心能力"
    public private(set) var endpoint = "尚未应用"
    public private(set) var location: IPLocation?
    public private(set) var guestIP: String?
    private let client: VPhoneCLIClient
    private let name: String
    private var probe = NativeDecodoProbe()
    #if VPHONE_CUSTOM_NATIVE_PROXY_WORKFLOW
    private var candidate: NativeDecodoCandidate?
    #endif

    public static var usesEmbeddedCredentials: Bool {
        #if VPHONE_CUSTOM_EMBEDDED_DECODO_CREDENTIALS
        true
        #else
        false
        #endif
    }

    public static var stagedWorkflowEnabled: Bool {
        #if VPHONE_CUSTOM_NATIVE_PROXY_WORKFLOW
        true
        #else
        false
        #endif
    }

    public init(client: VPhoneCLIClient, name: String) {
        self.client = client; self.name = name
        #if VPHONE_CUSTOM_NATIVE_INTERFACE_SELECTION
        if let physical = NativePhysicalNetwork.preferred() {
            interface = physical.kind; device = physical.device
        }
        #endif
    }

    public func selectPhysicalInterface() {
        #if VPHONE_CUSTOM_NATIVE_INTERFACE_SELECTION
        device = NativePhysicalNetwork.preferred(kind: interface)?.device ?? ""
        #endif
    }

    init(client: VPhoneCLIClient, name: String, probe: NativeDecodoProbe) {
        self.client = client; self.name = name; self.probe = probe

    }

    public func canSaveTested(location: DecodoLocation?) -> Bool {
        #if VPHONE_CUSTOM_NATIVE_PROXY_WORKFLOW
        candidate?.selection == selection(location)
        #else
        false
        #endif
    }

    public func saveTested(location: DecodoLocation? = nil) async {
        #if VPHONE_CUSTOM_NATIVE_PROXY_WORKFLOW
        await execute(apply: true, target: location, useTested: true)
        #else
        message = "当前构建未启用检测后保存功能。"
        #endif
    }

    #if VPHONE_CUSTOM_NATIVE_PROXY_WORKFLOW
    private func selection(_ target: DecodoLocation?) -> NativeDecodoSelection {
        .init(credentialsPath: Self.usesEmbeddedCredentials ? "" : credentialsPath, isp: isp, city: city, zip: zip,
              interface: interface, device: device, target: target)
    }
    #endif

    public func configuredLocation(in locations: [DecodoLocation]) -> DecodoLocation? {
        guard let context = try? client.context(name: name),
              let config = try? NativeDecodoService.savedConfiguration(directory: context.directory),
              config.host == "isp.decodo.com" else { return nil }
        let suffix = config.username.range(of: "-country-").map { String(config.username[$0.lowerBound...]) } ?? ""
        return locations.first { $0.suffix == suffix }
    }

    public func refresh() async {
        // A stopped VM still has saved settings; lack of a live socket must not erase them.
        if let context = try? client.context(name: name),
           let config = try? NativeDecodoService.savedConfiguration(directory: context.directory) {
            isp = config.host == "isp.decodo.com"
            #if !VPHONE_CUSTOM_NATIVE_INTERFACE_SELECTION
            interface = config.interface
            #endif
            endpoint = "\(config.host):\(config.port)（已保存）"
        }
        do {
            let status = try await client.networkStatus(name: name)
            supported = status.nativeProxySupported == true; enabled = status.nativeProxyEnabled == true
            endpoint = status.nativeProxyEndpoint ?? "尚未应用"
            if let context = try? client.context(name: name),
               let config = try? NativeDecodoService.savedConfiguration(directory: context.directory) {
                isp = config.host == "isp.decodo.com"
                #if !VPHONE_CUSTOM_NATIVE_INTERFACE_SELECTION
                interface = config.interface
                #endif
            }
            message = supported ? "当前核心支持原生代理；选择选项不会立即切换。" : "当前核心尚不支持原生 HTTPS 代理，无法应用此方案。"
        } catch { supported = false; message = "无法读取运行核心能力：" + error.localizedDescription }
    }

    public func waitForCore() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        message = "正在等待实例控制连接就绪，已检测的候选出口会保留…"
        for _ in 0..<30 {
            if (try? await client.networkStatus(name: name)) != nil { await refresh(); return }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
        message = "实例控制连接尚未就绪，请稍后重试；候选出口未应用。"
    }

    /// Tests a newly requested endpoint without changing any VM or Clash configuration.
    public func testDirect(location: DecodoLocation? = nil) async { await execute(apply: false, target: location) }
    public func rotate(location: DecodoLocation? = nil) async { await execute(apply: true, target: location) }

    private func execute(apply: Bool, target: DecodoLocation?, useTested: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        configurationMessage = nil
        defer { configurationMessage = message }
        location = nil; guestIP = nil
        var applied = false
        var reservedPort: Int?
        defer { if let reservedPort { Self.pendingPorts.remove(reservedPort) } }
        do {
            let context = try client.context(name: name)
            #if VPHONE_CUSTOM_NATIVE_PROXY_WORKFLOW
            let requested = selection(target)
            let tested = candidate
            candidate = nil
            #endif
            if apply {
                let status = try await client.networkStatus(name: name)
                supported = status.nativeProxySupported == true
                guard status.nativeProxySupported == true else { throw ProxyRouteError("此运行核心不支持原生代理，未修改任何出口") }
            }
            guard device.range(of: #"^en[0-9]+$"#, options: .regularExpression) != nil else { throw ProxyRouteError("未找到可用的物理网络，请连接 Wi-Fi 或以太网后重试；也可在高级网络设置中选择网卡") }
            try probe.validate(device, interface)
            let credentials = try NativeDecodoService.credentials(path: credentialsPath)
            let occupied = try NativeDecodoService.occupiedPorts(context: context).union(Self.pendingPorts)
            var config: NativeDecodoConfiguration
            #if VPHONE_CUSTOM_NATIVE_PROXY_WORKFLOW
            if useTested {
                guard let tested else { throw ProxyRouteError("请先选择地区并检测出口，再保存。") }
                try tested.validate(selection: requested, credentials: credentials, context: context, occupied: occupied)
                config = tested.config
            } else {
                config = try NativeDecodoService.configuration(context: context, credentials: credentials,
                    isp: isp, city: city, zip: zip, interface: interface, location: target, occupied: occupied)
            }
            #else
            config = try NativeDecodoService.configuration(context: context, credentials: credentials,
                isp: isp, city: city, zip: zip, interface: interface, location: target, occupied: occupied)
            #endif
            if isp { reservedPort = config.port; Self.pendingPorts.insert(config.port) }
            message = "正在检测所选地区的代理出口…"
            if !useTested { config.address = try await probe.resolve(config.host, device) }
            let detected = try await probe.probe(config, device)
            location = detected
            #if VPHONE_CUSTOM_NATIVE_PROXY_WORKFLOW
            guard selection(target) == requested else { throw ProxyRouteError("检测期间选项已改变，请重新检测。") }
            if useTested, detected.ip != tested?.location.ip {
                throw ProxyRouteError("供应商出口 IP 已变化，请重新检测后保存；未应用。")
            }
            if !apply {
                candidate = NativeDecodoCandidate(selection: requested, credentials: credentials,
                    config: config, directory: context.directory, executable: context.executable, location: detected)
            }
            #endif
            guard apply else {
                message = Self.stagedWorkflowEnabled
                    ? "检测通过：\(config.host):\(config.port)，IP \(detected.ip)。尚未保存，请点击保存并应用。"
                    : "独立直连检测成功；尚未应用到虚拟机。"
                return
            }
            guard try client.context(name: name).executable == context.executable else { throw ProxyRouteError("实例核心绑定发生变化，未应用") }
            message = "代理检测通过，正在保存并应用…"
            let file = try NativeDecodoService.save(config, context: context)
            try await client.setNativeProxy(name: name, path: file.path)
            applied = true; enabled = true
            endpoint = "\(config.host):\(config.port)"
            message = "已应用，正在验证虚拟机实际出口…"
            let status = try await client.networkStatus(name: name, probe: true)
            guestIP = status.egress?.ip
            if guestIP == location?.ip { message = "已应用原生出口，虚拟机实测 IP 与 Decodo 一致。" }
            else { message = "已应用；虚拟机检测尚未确认一致：\(status.egressError ?? guestIP ?? "未返回结果")。请点击“重新检测”。" }
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
        guestIP = nil
        message = "正在从虚拟机检测公网 IP…"
        do {
            let status = try await client.networkStatus(name: name, probe: true)
            guestIP = status.egress?.ip
            message = guestIP == nil ? (status.egressError ?? "未返回 IP") : "检测完成，未修改代理。"
        } catch { message = error.localizedDescription }
    }
}
