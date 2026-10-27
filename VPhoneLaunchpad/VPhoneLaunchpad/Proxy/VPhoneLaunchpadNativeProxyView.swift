import SwiftUI
import VPhoneWSCore

struct VPhoneLaunchpadNativeProxyView: View {
    @Bindable var value: NativeDecodoController
    var catalog: DecodoProxyController?
    let machine: VPhoneLaunchpadMachine
    @Environment(VPhoneLaunchpadModel.self) private var model
    let perform: (() async -> Void) async -> Void
    var body: some View {
        Form {
            Section("原生 HTTPS · 实验") {
                LabeledContent("当前网络路径", value: model.machines.state(of: machine.path) == .running
                    ? (value.enabled ? "原生 Decodo" : "原生 HTTPS 尚未启用") : "未运行，启动后读取实际路径")
                Picker("套餐", selection: $value.isp) {
                    Text("ISP · 按流量").tag(true)
                    Text("动态住宅 · ZIP").tag(false)
                }
                if !NativeDecodoController.usesEmbeddedCredentials {
                    TextField("本机凭据文件", text: $value.credentialsPath)
                }
                if value.isp { if let catalog { VPhoneLaunchpadLocationPicker(value: catalog) } }
                else { TextField("美国 ZIP", text: $value.zip) }
                DisclosureGroup("高级网络设置") {
                    Picker("物理网络", selection: $value.interface) {
                        Text("Wi-Fi").tag("wifi"); Text("以太网").tag("ethernet")
                    }.onChange(of: value.interface) { _, _ in value.selectPhysicalInterface() }
                    TextField("物理网卡", text: $value.device)
                    Text("仅在自动选择的网络不正确时调整。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("检测并应用") {
                    Task { await perform { await value.rotate(location: catalog?.selectedLocation) } }
                }.disabled(model.machines.state(of: machine.path) != .running || (value.isp && catalog?.selectedLocation == nil))
                Text("自动检测所选地区，检测通过后保存并应用，再验证虚拟机实际出口。检测失败不会切换出口。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("仅操作当前实例；切换会断开它的现有连接。ISP 换新端口，动态住宅使用独立五分钟会话。仅使用原生 HTTPS 代理，不自动改用其他网络方案。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let configurationMessage = value.configurationMessage {
                Section("设置结果") { Text(configurationMessage).textSelection(.enabled) }
            }
            Section("检测结果") {
                if !value.enabled {
                    Text("原生出口尚未应用；当前公网 IP 仅表示虚拟机现有网络出口。请点击“检测并应用”。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("代理入口", value: value.endpoint)
                if let location = value.location {
                    LabeledContent("代理出口 IP", value: location.ip)
                    LabeledContent("城市 / 地区", value: location.area)
                    LabeledContent("邮编 · Decodo/IPInfo", value: location.postal ?? "未知")
                }
                VPhoneLaunchpadCurrentIPView(path: machine.path)
                Button("重新检测") { Task { await perform { await value.detectGuest() } } }
                    .disabled(model.machines.state(of: machine.path) != .running)
                if model.machines.state(of: machine.path) != .running {
                    Text("请先启动此虚拟机，再检测实际公网 IP。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("启动此虚拟机") { Task { await model.machines.start(machine.path); await value.waitForCore() } }
                        .disabled(model.machines.state(of: machine.path) != .stopped)
                }
                if value.message != value.configurationMessage { Text(value.message).textSelection(.enabled) }
            }
            Text("实验范围：IPv4 TCP 与 DNS-over-HTTPS；其他 UDP/QUIC 被阻止，不绕过代理。当前运行的旧核心不会被自动更新或重启。")
                .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped).disabled(value.busy || VPhoneLaunchpadFlywheelWebAction.shared.active != nil)
            .onChange(of: model.machines.state(of: machine.path)) { _, state in
                if state == .running { Task { await value.waitForCore() } }
            }
    }
}
