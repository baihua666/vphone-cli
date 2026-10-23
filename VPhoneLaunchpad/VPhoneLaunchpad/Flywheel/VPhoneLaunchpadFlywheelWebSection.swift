import SwiftUI
import VPhoneFlywheel

struct VPhoneLaunchpadFlywheelWebSection: View {
    let machine: VPhoneLaunchpadMachine
    @Environment(VPhoneLaunchpadModel.self) private var model
    @AppStorage(VPhoneFlywheelWebPage.urlPreferenceKey) private var url = ""
    @AppStorage(VPhoneFlywheelWebPage.includeIPPreferenceKey) private var includeIP = true
    private var action: VPhoneLaunchpadFlywheelWebAction { .shared }
    private var parameters: VPhoneFlywheelURLParameterStore { .shared }

    var body: some View {
        Section("FLYWHEEL") {
            VPhoneLaunchpadFlywheelNetworkView(machine: machine)
            TextField("业务网页 URL", text: $url, prompt: Text("https://…"))
                .textFieldStyle(.roundedBorder)
                .disabled(action.active != nil)
            Text("此 Mac 共用的 FLYWHEEL 地址与参数选择，自动保存。")
                .font(.caption).foregroundStyle(.secondary)
            VPhoneLaunchpadFlywheelURLParametersView(includeIP: $includeIP)
                .disabled(action.active != nil)
            .onChange(of: includeIP) { action.clearMessage(for: machine.path) }
            .onChange(of: parameters.parameters) { action.clearMessage(for: machine.path) }
            Button("打开业务网页", systemImage: "safari") {
                action.open(url: url, includeIP: includeIP, parameters: parameters.parameters,
                    machine: machine, library: model.machines)
            }
            .disabled(action.active != nil || parameters.error != nil || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || model.machines.state(of: machine.path) != .running)
            if action.active == machine.path {
                ProgressView().controlSize(.small)
            }
            if let message = action.messages[machine.path] {
                Text(message).font(.callout).textSelection(.enabled)
            }
            if model.machines.state(of: machine.path) != .running {
                Text("实例未运行，无法读取 guest IP。可先准备网络与出口，再打开网页。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct VPhoneLaunchpadFlywheelURLParametersView: View {
    @Binding var includeIP: Bool
    @Bindable private var store = VPhoneFlywheelURLParameterStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("URL 参数").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("新增参数", systemImage: "plus") { store.parameters.append(.init()) }
                    .disabled(store.error != nil)
            }
            HStack {
                Toggle("ip", isOn: $includeIP).toggleStyle(.checkbox).fixedSize()
                Text("打开时自动获取并附加实测公网 IP")
                    .foregroundStyle(.secondary).textSelection(.enabled)
                    .strikethrough(!includeIP)
                Spacer(minLength: 0)
                Image(systemName: "lock").foregroundStyle(.secondary).help("ip 名称固定，值自动取当前虚拟机出口 IP。")
            }
            ForEach($store.parameters) { $parameter in
                HStack(spacing: 6) {
                    Toggle("发送参数", isOn: $parameter.isEnabled).labelsHidden().toggleStyle(.checkbox)
                        .accessibilityLabel("发送自定义参数 \(parameter.name)")
                    TextField("参数名", text: $parameter.name)
                        .accessibilityLabel("自定义参数名")
                    TextField("参数值", text: $parameter.value)
                        .accessibilityLabel("自定义参数值")
                    Button("删除参数", systemImage: "minus.circle") {
                        let id = parameter.id
                        store.parameters.removeAll { $0.id == id }
                    }.labelStyle(.iconOnly).help("删除此参数行")
                }
                .textFieldStyle(.roundedBorder)
                .disabled(store.error != nil)
            }
            if let error = store.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Text("同名参数以列表为准；未勾选不发送，空白行忽略。ip 自动获取，其它原 URL 参数保留。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
