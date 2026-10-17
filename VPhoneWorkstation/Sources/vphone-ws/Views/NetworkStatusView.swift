import SwiftUI
import VPhoneWSCore

struct NetworkStatusView: View {
    let row: VMRow
    let client: VPhoneCLIClient
    var proxyRevision = 0
    @State private var status: VMNetworkStatus?
    @State private var error: String?
    @State private var busy = false
    @State private var request: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "网络状态")
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("刷新状态") { load(probe: false) }.disabled(!row.isRunning || busy)
                Button("检测 guest 出口 IP") { load(probe: true) }.disabled(!row.isRunning || busy)
            }
            LabeledContent("已保存模式", value: row.report.network?.mode ?? "未知")
            if !row.isRunning {
                Text("实例已停止，启动后可读取实时网络状态。")
            } else if let status {
                LabeledContent("运行中模式", value: status.attachment ?? "无网卡")
                LabeledContent("链路", value: status.link ?? "未知")
                LabeledContent("Guest 地址分配设置", value: status.guestIPv4 ?? "未知")
                LabeledContent("Guest 实际 IPv4（en0）", value: status.guestInterfaceIPv4 ?? "尚未取得（guest 未就绪或旧运行版本）")
                if let egress = status.egress {
                    LabeledContent("公网 IPv4（最近检测）", value: egress.ip)
                    LabeledContent("检测时间", value: egress.checkedAt)
                    Text("来源：guest → \(egress.source)").textSelection(.enabled)
                } else { Text("公网 IPv4：尚未检测或检测失败") }
                if let failure = status.egressError { Text(failure).foregroundStyle(.orange) }
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Text("出口检测会从虚拟 iPhone 向 api.ipify.org 发起 HTTPS 请求；不修改 Clash。结果不代表全部 App、DNS 或 UDP 的出口，也不保证静态 IP。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
        .task(id: row.isRunning) {
            request?.cancel()
            status = nil
            if row.isRunning { load(probe: false) }
        }
        .onDisappear { request?.cancel() }
        .onChange(of: proxyRevision) { _, _ in load(probe: false) }
    }

    private func load(probe: Bool) {
        request?.cancel()
        busy = true
        error = nil
        status = nil
        request = Task { @MainActor in
            do {
                let result = try await client.networkStatus(name: row.report.name, probe: probe)
                try Task.checkCancellation()
                status = result
            } catch {
                if !Task.isCancelled {
                    self.error = (error as? VPhoneCLIError)?.userMessage ?? String(describing: error)
                }
            }
            if !Task.isCancelled { busy = false }
        }
    }
}
