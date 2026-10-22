import Foundation
import Observation

/// Shared workflow for management clients. Construction and refresh never alter routing.
@MainActor @Observable
public final class DecodoProxyController {
    public var zip = ""
    public var username = ""
    public var password = ""
    public private(set) var route: VMProxyRoute?
    public private(set) var session: DecodoSession?
    public private(set) var egress: VMNetworkStatus.Egress?
    public private(set) var busy = false
    public private(set) var message = ""
    private let client: VPhoneCLIClient
    private let proxy: ClashProxyService
    private let name: String

    public init(client: VPhoneCLIClient, proxy: ClashProxyService, name: String) {
        self.client = client; self.proxy = proxy; self.name = name
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
        do {
            let context = try client.context(name: name)
            route = try await proxy.route(context: context)
            session = try await proxy.decodoSession(context: context)
            if let session { zip = session.zip }
            message = "已读取配置，未修改出口。"
        } catch { message = error.localizedDescription }
    }

    public func apply(rotate: Bool) async {
        guard !busy, let expected = route else { return }
        busy = true; egress = nil; defer { busy = false }
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
            if rotate {
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
        } catch {
            message = (applied ? "规则已生效，后续检测失败：" : "未完成出口变更：") + error.localizedDescription
            if !applied { route = nil }
        }
    }
}
