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
                Picker("物理网络", selection: $value.interface) {
                    Text("Wi-Fi").tag("wifi"); Text("以太网").tag("ethernet")
                }
                TextField("检测使用的网卡", text: $value.device)
                Text("例如 Wi-Fi 的 en1，请按此 Mac 的实际网卡填写。")
                    .font(.caption).foregroundStyle(.secondary)
                Button(NativeDecodoController.stagedWorkflowEnabled ? "检测所选地区出口" : "直连检测（不应用到虚拟机）") {
                    Task { await value.testDirect(location: catalog?.selectedLocation) }
                }.disabled(value.isp && catalog?.selectedLocation == nil)
                HStack {
                    if NativeDecodoController.stagedWorkflowEnabled {
                        Button("保存并应用已检测出口") { Task { await perform { await value.saveTested(location: catalog?.selectedLocation) } } }
                            .disabled(model.machines.state(of: machine.path) != .running || !value.canSaveTested(location: catalog?.selectedLocation))
                    } else {
                        Button(value.enabled ? "一键换 IP" : "应用原生出口") { Task { await perform { await value.rotate(location: catalog?.selectedLocation) } } }
                            .disabled(!value.supported || (value.isp && catalog?.selectedLocation == nil))
                    }
                }
                if NativeDecodoController.stagedWorkflowEnabled {
                    Text("选择地区 → 检测候选 IP → 保存同一出口 → 虚拟机验证。再次检测会申请新的候选入口；保存前复检，失败不切换。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("仅操作当前实例；切换会断开它的现有连接。ISP 换新端口，动态住宅使用独立五分钟会话。仅使用原生 HTTPS 代理，不自动改用其他网络方案。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("检测结果") {
                LabeledContent("代理入口", value: value.endpoint)
                if let location = value.location {
                    LabeledContent("候选出口 IP · 直连检测", value: location.ip)
                    LabeledContent("城市 / 地区", value: location.area)
                    LabeledContent("邮编 · Decodo/IPInfo", value: location.postal ?? "未知")
                }
                VPhoneLaunchpadCurrentIPView(path: machine.path)
                Button("检测当前虚拟机 IP") { Task { await perform { await value.detectGuest() } } }
                    .disabled(model.machines.state(of: machine.path) != .running)
                if model.machines.state(of: machine.path) != .running {
                    Text("请先启动此虚拟机，再检测实际公网 IP。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("启动此虚拟机") { Task { await model.machines.start(machine.path); await value.waitForCore() } }
                        .disabled(model.machines.state(of: machine.path) != .stopped)
                }
                Text(value.message).textSelection(.enabled)
            }
            Text("实验范围：IPv4 TCP 与 DNS-over-HTTPS；其他 UDP/QUIC 被阻止，不绕过代理。当前运行的旧核心不会被自动更新或重启。")
                .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped).disabled(value.busy || VPhoneLaunchpadFlywheelWebAction.shared.active != nil)
            .onChange(of: model.machines.state(of: machine.path)) { _, state in
                if state == .running { Task { await value.waitForCore() } }
            }
    }
}
