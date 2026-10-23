import SwiftUI

/// Shared by the platform inspector and the business registration sheet.
struct VPhoneLaunchpadFlywheelNetworkView: View {
    let machine: VPhoneLaunchpadMachine
    @Environment(VPhoneLaunchpadModel.self) private var model
    @State private var preparing = false
    private var network: VPhoneLaunchpadFlywheelNetwork { .shared }
    private var busy: Bool { VPhoneLaunchpadFlywheelWebAction.shared.active != nil || preparing }

    var body: some View {
        @Bindable var network = network
        VStack(alignment: .leading, spacing: 8) {
            VPhoneLaunchpadCurrentIPView(path: machine.path)
            Text(network.messages[machine.path] ?? "")
                .font(.callout).textSelection(.enabled)
            HStack {
                Button("检查网络") { Task { await network.check(machine, library: model.machines) } }
                Button("准备网络与出口…") { preparing = true }
            }.disabled(busy)
        }
        .sheet(isPresented: $preparing) {
            VPhoneLaunchpadFlywheelNetworkPreparationView(machine: machine)
                .environment(model)
        }
        .task(id: "\(machine.path.url.path)|\(model.machines.state(of: machine.path))|\(machine.network.mode)") {
            await network.check(machine, library: model.machines)
        }
    }
}

struct VPhoneLaunchpadFlywheelNetworkPreparationView: View {
    let machine: VPhoneLaunchpadMachine
    @Environment(VPhoneLaunchpadModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var error: String?
    private var network: VPhoneLaunchpadFlywheelNetwork { .shared }

    var body: some View {
        @Bindable var network = network
        VStack(alignment: .leading, spacing: 16) {
            Text("准备业务网络 · \(machine.name)").font(.headline)
            Text("仅操作此实例：必要时正常关闭、设置 tunnel 并启动；优先复用已生效的 DECODO，否则通过已有本机代理凭据配置原生 ISP 出口，再从 guest 验证公网 IP。")
            TextField("新出口城市参数", text: $network.city)
            TextField("检测使用的物理网卡", text: $network.device)
            TextField("本机代理凭据文件", text: $network.credentialsPath)
            Text("默认城市为 New York。网卡需与本机 Wi-Fi 对应；复用已有 DECODO 时不会重新申请出口。")
                .font(.caption).foregroundStyle(.secondary)
            if let message = network.messages[machine.path] { Text(message).textSelection(.enabled) }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("关闭") { dismiss() }
                Button("准备并验证") {
                    busy = true
                    error = nil
                    Task {
                        defer { busy = false }
                        do {
                            _ = try await network.prepare(machine, library: model.machines)
                            dismiss()
                        } catch { self.error = VPhoneLaunchpadError.message(for: error) }
                    }
                }
            }
        }.padding(20).frame(width: 570).disabled(busy).interactiveDismissDisabled(busy)
    }
}

/// A single measured result shared by network checks, proxy actions and Safari opens.
struct VPhoneLaunchpadCurrentIPView: View {
    let path: VPhoneLaunchpadMachinePath
    var body: some View {
        let result = VPhoneLaunchpadFlywheelNetwork.shared.measurements[path]
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("当前实测公网 IP", value: result?.ip ?? "尚未检测 / 待重新检测")
            if let result {
                LabeledContent("检测时间", value: result.checkedAt.formatted(date: .numeric, time: .standard))
            }
        }.textSelection(.enabled)
    }
}
