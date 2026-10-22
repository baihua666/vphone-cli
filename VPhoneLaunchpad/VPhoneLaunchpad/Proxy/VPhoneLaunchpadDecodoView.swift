import SwiftUI
import VPhoneWSCore

/// One service serializes proxy writes across all Launchpad windows.
private enum VPhoneLaunchpadProxyServices {
    static let proxy = ClashProxyService()
}

struct VPhoneLaunchpadDecodoView: View {
    let machine: VPhoneLaunchpadMachine
    let roots: [String]
    let isRunning: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var controller: DecodoProxyController?
    @State private var credentialsPath = DecodoLocalConfiguration.resolvedPath ?? DecodoLocalConfiguration.defaultPath

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Decodo · \(machine.name)").font(.headline)
            if let controller {
                form(controller)
            } else {
                ProgressView()
            }
            HStack { Spacer(); Button("完成") { dismiss() }.disabled(controller?.busy == true) }
        }
        .padding(20)
        .frame(width: 560)
        .task {
            guard controller == nil else { return }
            let store = VPhoneLaunchpadBundleStore.root
            let client = VPhoneCLIClient(executable: store, libraryRoot: machine.path.libraryRoot,
                runner: SystemCLIRunner(), launchpadStore: store, isolationRoots: roots)
            let value = DecodoProxyController(client: client, proxy: VPhoneLaunchpadProxyServices.proxy, name: machine.name)
            controller = value
            await value.refresh()
            // No file is required when rotating an already configured session.
            value.loadCredentials(path: FileManager.default.fileExists(atPath: credentialsPath) ? credentialsPath : nil)
        }
    }

    @ViewBuilder
    private func form(_ value: DecodoProxyController) -> some View {
        @Bindable var value = value
        Form {
            Section("本机凭据") {
                TextField("配置文件", text: $credentialsPath)
                Button("读取文件") { value.loadCredentials(path: credentialsPath) }
                TextField("原始代理用户名", text: $value.username)
                SecureField("代理密码", text: $value.password)
            }
            Section("独立出口") {
                TextField("美国 ZIP 邮编", text: $value.zip, prompt: Text("10001"))
                if let route = value.route { LabeledContent("当前出口", value: route.selected) }
                if let session = value.session {
                    LabeledContent("会话", value: String(session.id.prefix(8)))
                    LabeledContent("已保存 ZIP", value: session.zip)
                }
                HStack {
                    Button("刷新配置") { Task { await value.refresh() } }
                    Button("保存、应用并检测") { Task { await value.apply(rotate: false) } }
                        .disabled(!canApply(value) || value.username.isEmpty || value.password.isEmpty)
                    Button("换新 IP") { Task { await value.apply(rotate: true) } }
                        .disabled(!canApply(value) || value.session == nil)
                }
            }
            if let egress = value.egress {
                Section("Guest 实测") {
                    LabeledContent("公网 IPv4", value: egress.ip)
                    LabeledContent("检测时间", value: egress.checkedAt)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(value.busy)
        if value.busy { ProgressView().controlSize(.small) }
        Text(value.message).font(.callout).textSelection(.enabled)
        if !isRunning { Text("请先启动此虚拟机，再应用或更换出口。").foregroundStyle(.secondary) }
        Text("每台机器使用独立的五分钟 IP Lock 会话；点击换新会话才执行操作，不会定时断网。随机重复 IP 仍可能发生。ZIP 是区域筛选；此处验证 HTTPS/TCP 出口，不保证全部 App、DNS 或 UDP。")
            .font(.caption).foregroundStyle(.secondary)
    }

    private func canApply(_ value: DecodoProxyController) -> Bool {
        isRunning && machine.network.mode == "tunnel" && value.route != nil
            && value.zip.range(of: #"^[0-9]{5}$"#, options: .regularExpression) != nil
    }
}
