import SwiftUI
import VPhoneWSCore

struct ProxyRouteView: View {
    let row: VMRow
    let client: VPhoneCLIClient
    let proxy: ClashProxyService
    var onApplied: () -> Void
    @State private var route: VMProxyRoute?
    @State private var selected = ""
    @State private var busy = false
    @State private var message: String?
    @State private var egress: VMNetworkStatus.Egress?
    @State private var lifecycle = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "代理出口 · Clash Verge")
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("刷新出口") { refresh() }.disabled(busy)
            }
            if let route {
                LabeledContent("已保存 / 已生效", value: route.selected)
                Picker("本实例出口", selection: $selected) {
                    if !route.choices.contains(route.selected) { Text(route.selected).tag(route.selected) }
                    ForEach(route.choices, id: \.self) { Text($0).tag($0) }
                }.disabled(busy)
                Button("应用出口并检测") { apply() }.disabled(busy || !row.isRunning || selected.isEmpty)
            }
            if let message { Text(message).font(.caption).textSelection(.enabled) }
            if let egress {
                LabeledContent("切换后 guest 公网 IPv4", value: egress.ip)
                Text("检测时间：\(egress.checkedAt)").font(.caption)
            }
            Text("复用当前订阅节点，仅修改本实例的进程路径规则并断开其旧连接。实例需使用独立运行程序与 tunnel 网络；应用后自动从 guest 检测公网 IP。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
        .task { refresh() }
        .onChange(of: row.isRunning) { _, _ in egress = nil; lifecycle = UUID() }
        .onDisappear { lifecycle = UUID() }
    }

    private func refresh() {
        busy = true; message = nil; route = nil; egress = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                guard row.report.network?.mode == "tunnel" else { throw NSError(domain: "需要 tunnel 网络模式", code: 1) }
                let result = try await proxy.route(context: client.context(name: row.report.name))
                route = result; selected = result.selected
            } catch { message = error.localizedDescription }
        }
    }

    private func apply() {
        guard let route else { return }
        busy = true; message = nil; egress = nil
        let operationLifecycle = lifecycle
        Task { @MainActor in
            defer { busy = false }
            do {
                let context = try client.context(name: row.report.name)
                let network = try await client.networkStatus(name: row.report.name)
                guard network.attachment?.lowercased().contains("tunnel") == true else {
                    message = "运行中网络不是 tunnel，未修改出口"; return
                }
                try await proxy.apply(context: context, target: selected, expected: route)
                self.route = try await proxy.route(context: context)
                message = "规则已保存并生效，正在检测 guest 公网 IP。"
                onApplied()
                let result = try await client.networkStatus(name: row.report.name, probe: true)
                guard operationLifecycle == lifecycle else { return }
                egress = result.egress
                message = result.egressError.map { "规则已生效，但 guest 检测失败：\($0)" }
                    ?? (result.egress == nil ? "规则已生效，但未取得 guest 公网 IP" : "规则已保存并生效，guest 出口检测完成。")
            } catch {
                message = error.localizedDescription
                self.route = nil
            }
        }
    }
}
