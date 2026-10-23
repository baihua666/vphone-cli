import SwiftUI
import VPhoneWSCore

struct VPhoneLaunchpadNativeProxyView: View {
    @Bindable var value: NativeDecodoController
    var catalog: DecodoProxyController?
    let machine: VPhoneLaunchpadMachine
    let perform: (() async -> Void) async -> Void
    var body: some View {
        Form {
            Section("原生 HTTPS · 实验") {
                LabeledContent("当前网络路径", value: value.enabled ? "原生 Decodo" : "宿主机 / Clash")
                Picker("套餐", selection: $value.isp) {
                    Text("ISP · 按流量").tag(true)
                    Text("动态住宅 · ZIP").tag(false)
                }
                TextField("本机凭据文件", text: $value.credentialsPath)
                if value.isp { if let catalog { VPhoneLaunchpadLocationPicker(value: catalog) } }
                else { TextField("美国 ZIP", text: $value.zip) }
                Picker("物理网络", selection: $value.interface) {
                    Text("Wi-Fi").tag("wifi"); Text("以太网").tag("ethernet")
                }
                TextField("检测使用的网卡", text: $value.device)
                Text("例如 Wi-Fi 的 en1，请按此 Mac 的实际网卡填写。凭据文件只读，不写入 Git。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("直连检测（不应用到虚拟机）") { Task { await value.testDirect(location: catalog?.selectedLocation) } }.disabled(value.isp && catalog?.selectedLocation == nil)
                HStack {
                    Button(value.enabled ? "一键换 IP" : "应用原生出口") { Task { await perform { await value.rotate(location: catalog?.selectedLocation) } } }
                        .disabled(!value.supported || (value.isp && catalog?.selectedLocation == nil))
                    Button("切回 Clash") { Task { await perform { await value.restoreClash() } } }.disabled(!value.enabled)
                }
                Text("仅操作当前实例；切换会断开它的现有连接。ISP 换新端口，动态住宅使用独立五分钟会话。不会自动切回或直连互联网。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("检测结果") {
                LabeledContent("代理入口", value: value.endpoint)
                if let location = value.location {
                    LabeledContent("城市 / 地区", value: location.area)
                    LabeledContent("邮编 · Decodo/IPInfo", value: location.postal ?? "未知")
                }
                VPhoneLaunchpadCurrentIPView(path: machine.path)
                Button("检测当前虚拟机 IP") { Task { await perform { await value.detectGuest() } } }
                Text(value.message).textSelection(.enabled)
            }
            Text("实验范围：IPv4 TCP 与 DNS-over-HTTPS；其他 UDP/QUIC 被阻止，不绕过代理。当前运行的旧核心不会被自动更新或重启。")
                .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped).disabled(value.busy)
    }
}
