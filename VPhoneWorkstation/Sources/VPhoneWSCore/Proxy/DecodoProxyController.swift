import Foundation
import Observation

/// Shared workflow for management clients. Construction and refresh never alter routing.
@MainActor @Observable
public final class DecodoProxyController {
    public var zip = ""
    public private(set) var locations: [DecodoLocation] = []
    public var selectedLocation: DecodoLocation?
    public private(set) var locationsMessage = "尚未同步官网地区"
    public var ispCity = "New York"
    public var username = ""
    public var password = ""
    public private(set) var route: VMProxyRoute?
    public private(set) var session: DecodoSession?
    public private(set) var egress: VMNetworkStatus.Egress?
    public private(set) var providerLocation: IPLocation?
    public private(set) var providerMessage = ""
    public private(set) var location: IPLocation?
    public private(set) var locationMessage = ""
    public private(set) var busy = false
    public private(set) var message = ""
    private let client: VPhoneCLIClient
    private let proxy: ClashProxyService
    private let name: String
    private let lookupProvider: (@Sendable (VMCommandContext, String) async throws -> IPLocation)?
    private let lookupLocation: @Sendable (String) async throws -> IPLocation

    public init(client: VPhoneCLIClient, proxy: ClashProxyService, name: String,
                lookupLocation: @escaping @Sendable (String) async throws -> IPLocation = IPLocationLookup.lookup,
                lookupProvider: (@Sendable (VMCommandContext, String) async throws -> IPLocation)? = nil) {
        self.client = client; self.proxy = proxy; self.name = name
        self.lookupLocation = lookupLocation; self.lookupProvider = lookupProvider
    }

    public func syncLocations() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let values = try await DecodoLocations.fetch()
            locations = values
            if let selectedLocation, !values.contains(selectedLocation) { self.selectedLocation = nil }
            locationsMessage = "已从 Decodo 同步 \(values.count - 1) 个地区 · \(Date().formatted(date: .omitted, time: .shortened))"
        } catch {
            locations = []; selectedLocation = nil
            locationsMessage = "同步失败：" + error.localizedDescription
        }
    }

    public func loadCredentials(path: String?) {
        do {
            if let local = try DecodoLocalConfiguration.load(path: path) {
                username = local.username; password = local.password
                if zip.isEmpty { zip = local.zip }
                message += " 已读取本机凭据；尚未修改出口。"
            } else { message += " 未找到本机凭据，可手动填写账号密码。" }
        } catch { message = error.localizedDescription }
    }

    public func refresh() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        route = nil; session = nil; egress = nil
        location = nil; locationMessage = ""; providerLocation = nil; providerMessage = ""
        do {
            let context = try client.context(name: name)
            route = try await proxy.route(context: context)
            session = try await proxy.decodoSession(context: context)
            if let session { zip = session.zip }
            if let city = try await proxy.ispCity(context: context) { ispCity = city.replacingOccurrences(of: "_", with: " ") }
            message = "已读取配置，未修改出口。"
        } catch { message = error.localizedDescription }
    }

    /// Only invokes the bound CLI's network probe. Never writes Clash or disconnects connections.
    public func detectCurrentIP() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        egress = nil; location = nil; locationMessage = ""; providerLocation = nil; providerMessage = ""
        message = "正在从虚拟机检测当前 IP；不会修改代理。"
        do {
            let context = try client.context(name: name)
            let result = try await client.networkStatus(name: name, probe: true)
            guard try client.context(name: name).executable == context.executable else {
                throw ProxyRouteError("实例绑定已变化，请重新检测")
            }
            if let error = result.egressError { throw ProxyRouteError(error) }
            guard let measured = result.egress else { throw ProxyRouteError("未取得虚拟机公网 IP") }
            egress = measured
            message = "检测成功，未修改代理。结果仅代表检测时的 HTTPS 出口。"
            await resolveLocation()
        } catch { message = "检测失败，未修改代理：" + error.localizedDescription }
    }

    private func resolveLocation() async {
        guard let egress else { return }
        providerMessage = "正在查询 Decodo/IPInfo…"
        do {
            let context = try client.context(name: name)
            if let lookupProvider { providerLocation = try await lookupProvider(context, egress.ip) }
            else { providerLocation = try await proxy.decodoLocation(context: context, expectedIP: egress.ip) }
            providerMessage = "来源：Decodo / IPInfo；已核对与虚拟机实测 IP 一致。"
        } catch { providerMessage = "Decodo/IPInfo 暂不可用：" + error.localizedDescription }
        locationMessage = "正在查询第三方归属地…"
        do {
            location = try await lookupLocation(egress.ip)
            locationMessage = "来源：\(location?.source ?? "未知")；IP 数据库估算，不是设备 GPS 或街道地址。"
        } catch { locationMessage = "IP 已测得，归属地查询失败：" + error.localizedDescription }
    }

    public var locationComparison: String {
        guard let primary = providerLocation, let other = location else {
            return "尚未取得两份结果，无法比较；未用第三方结果替代 Decodo/IPInfo。"
        }
        var differences: [String] = []
        for (label, a, b) in [("国家", primary.country, other.country), ("地区", primary.region, other.region),
                               ("城市", primary.city, other.city), ("邮编", primary.postal, other.postal)] {
            if let a, let b, !a.isEmpty, !b.isEmpty, a.lowercased() != b.lowercased() { differences.append(label) }
        }
        return differences.isEmpty
            ? "双方已提供的字段一致；缺失字段不参与比较。IP 归属地不是 GPS 或街道地址。"
            : "数据库差异：" + differences.joined(separator: "、") + "不一致；不能保证目标 App 使用相同定位。"
    }

    public func apply(rotate: Bool, target: String? = nil, cityISP: Bool = false) async {
        guard !busy, let expected = route else { return }
        busy = true; egress = nil; defer { busy = false }
        location = nil; locationMessage = ""; providerLocation = nil; providerMessage = ""
        var applied = false
        do {
            let context = try client.context(name: name)
            let network = try await client.networkStatus(name: name)
            guard network.attachment?.lowercased().contains("tunnel") == true else {
                throw ProxyRouteError("运行中网络不是 tunnel，未修改出口")
            }
            guard try client.context(name: name).executable == context.executable else {
                throw ProxyRouteError("实例绑定已变化，请刷新后重试")
            }
            if cityISP {
                guard let selectedLocation, locations.contains(selectedLocation) else { throw ProxyRouteError("请同步并选择官网提供的地区，未修改出口") }; try await proxy.configureISP(context: context, city: ispCity, expected: expected, location: selectedLocation)
            } else if let target {
                try await proxy.apply(context: context, target: target, expected: expected)
            } else if rotate {
                session = try await proxy.rotateDecodo(context: context, zip: zip, expected: expected)
            } else {
                session = try await proxy.configureDecodo(context: context, username: username,
                    password: password, zip: zip, expected: expected)
            }
            applied = true
            route = try await proxy.route(context: context)
            message = "规则已保存并生效，正在检测 guest 公网 IP。"
            guard try client.context(name: name).executable == context.executable else {
                throw ProxyRouteError("实例绑定已变化，未进行出口检测，请刷新")
            }
            let result = try await client.networkStatus(name: name, probe: true)
            egress = result.egress
            message = result.egressError.map { "规则已生效，guest 检测失败：\($0)" }
                ?? (egress == nil ? "规则已生效，未取得 guest 公网 IP。" : "规则已生效，guest 出口检测成功。")
            await resolveLocation()
            if cityISP {
                if let location = providerLocation {
                    let requested = selectedLocation.map { DecodoLocation.token($0.city) } ?? ""
                    let actual = try? DecodoISP.city(location.city ?? "")
                    if selectedLocation?.kind == .city && actual != requested {
                        message += " 实测归属地与目标城市不一致，请核对，不视为定位通过。"
                    }
                } else { message += " 尚未验证目标城市归属地。" }
            }
        } catch {
            message = (applied ? "规则已生效，后续检测失败：" : "未完成出口变更：") + error.localizedDescription
            if !applied { route = nil }
        }
    }
}
