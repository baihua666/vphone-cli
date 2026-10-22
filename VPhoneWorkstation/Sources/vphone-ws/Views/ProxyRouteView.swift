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
    @State private var adding = false
    @State private var configuringDecodo = false
    @State private var decodo: DecodoSession?
    @State private var zip = ""
    @State private var decodoError: String?

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
                HStack {
                    Button("添加已购代理 IP") { adding = true }.disabled(busy)
                    Button("应用出口并检测") { apply() }.disabled(busy || !row.isRunning || selected.isEmpty)
                }
            }
            if route != nil {
                Divider()
                HStack {
                    Text("Decodo · 美国").font(.subheadline)
                    TextField("五位 ZIP 邮编", text: $zip).frame(width: 130).disabled(busy)
                    Button(decodo == nil ? "配置账号" : "修改账号") { configuringDecodo = true }
                        .disabled(busy || !row.isRunning)
                    Button("换新 IP 并检测") { apply(rotate: true) }
                        .disabled(busy || !row.isRunning || decodo == nil || zip.range(of: #"^[0-9]{5}$"#, options: .regularExpression) == nil)
                }
                if let decodoError { Text(decodoError).font(.caption).foregroundStyle(.secondary) }
                if let decodo {
                    Text("已保存 ZIP：\(decodo.zip) · 五分钟 IP Lock · 会话 \(decodo.id.prefix(8))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("每台实例独立会话；到期由供应商处理，不会在此处自动断网或定时换 IP。点击按钮会重新申请会话，随机重复 IP 仍可能发生。HTTPS/TCP 代理；不承诺 UDP 出口。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message { Text(message).font(.caption).textSelection(.enabled) }
            if let egress {
                LabeledContent("切换后 guest 公网 IPv4", value: egress.ip)
                Text("检测时间：\(egress.checkedAt)").font(.caption)
            }
            Text("可选择当前订阅节点或手动添加的已购代理 IP。切换仅修改本实例规则并断开其旧连接；需独立运行程序与 tunnel 网络。显示的公网 IP 为 guest 实测结果，不代表静态或独享。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
        .task { refresh() }
        .onChange(of: row.isRunning) { _, _ in lifecycle = UUID(); refresh() }
        .onDisappear { lifecycle = UUID() }
        .sheet(isPresented: $configuringDecodo) {
            DecodoProxySheet(initialZIP: zip) { apply(credentials: $0) }
        }
        .sheet(isPresented: $adding) {
            if let route {
                ManualProxySheet(proxy: proxy, client: client, machine: row.report.name, route: route) { name in
                    refresh(preferred: name)
                }
            }
        }
    }

    private func refresh(preferred: String? = nil) {
        busy = true; message = nil; route = nil; egress = nil; decodo = nil
        let operationLifecycle = lifecycle
        Task { @MainActor in
            defer { if operationLifecycle == lifecycle { busy = false } }
            do {
                guard row.report.network?.mode == "tunnel" else { throw NSError(domain: "需要 tunnel 网络模式", code: 1) }
                let result = try await proxy.route(context: client.context(name: row.report.name))
                guard operationLifecycle == lifecycle else { return }
                route = result
                selected = preferred.flatMap { result.choices.contains($0) ? $0 : nil } ?? result.selected
                if preferred != nil { message = "代理已保存；点击‘应用出口并检测’切换此实例。" }
                await refreshDecodo(lifecycle: operationLifecycle)
            } catch { if operationLifecycle == lifecycle { message = error.localizedDescription } }
        }
    }

    private func refreshDecodo(lifecycle operationLifecycle: UUID) async {
        do {
            let session = try await proxy.decodoSession(context: client.context(name: row.report.name))
            guard operationLifecycle == lifecycle else { return }
            decodo = session; decodoError = nil
            zip = session?.zip ?? zip
        } catch {
            guard operationLifecycle == lifecycle else { return }
            decodo = nil; decodoError = error.localizedDescription
        }
    }

    private func apply(credentials: DecodoProxySheet.Input? = nil, rotate: Bool = false) {
        guard let route else { return }
        busy = true; message = nil; egress = nil
        let operationLifecycle = lifecycle
        Task { @MainActor in
            defer { if operationLifecycle == lifecycle { busy = false } }
            do {
                let context = try client.context(name: row.report.name)
                let network = try await client.networkStatus(name: row.report.name)
                guard operationLifecycle == lifecycle else { return }
                guard network.attachment?.lowercased().contains("tunnel") == true else {
                    message = "运行中网络不是 tunnel，未修改出口"; return
                }
                if let credentials {
                    _ = try await proxy.configureDecodo(context: context, username: credentials.username,
                        password: credentials.password, zip: credentials.zip, expected: route)
                } else if rotate {
                    _ = try await proxy.rotateDecodo(context: context, zip: zip, expected: route)
                } else {
                    try await proxy.apply(context: context, target: selected, expected: route)
                }
                guard operationLifecycle == lifecycle else { return }
                let updatedRoute = try await proxy.route(context: context)
                guard operationLifecycle == lifecycle else { return }
                self.route = updatedRoute
                await refreshDecodo(lifecycle: operationLifecycle)
                guard operationLifecycle == lifecycle else { return }
                selected = self.route?.selected ?? selected
                zip = decodo?.zip ?? zip
                message = "规则已保存并生效，正在检测 guest 公网 IP。"
                onApplied()
                let result = try await client.networkStatus(name: row.report.name, probe: true)
                guard operationLifecycle == lifecycle else { return }
                egress = result.egress
                message = result.egressError.map { "规则已生效，但 guest 检测失败：\($0)" }
                    ?? (result.egress == nil ? "规则已生效，但未取得 guest 公网 IP" : "规则已保存并生效，guest 出口检测完成。")
            } catch {
                guard operationLifecycle == lifecycle else { return }
                message = error.localizedDescription
                self.route = nil
            }
        }
    }
}
