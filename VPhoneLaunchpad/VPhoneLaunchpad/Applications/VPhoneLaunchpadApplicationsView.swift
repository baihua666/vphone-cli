#if VPHONE_CUSTOM_APPLICATION_MANAGEMENT
import SwiftUI
import UniformTypeIdentifiers
import VPhoneApplicationManagement

struct VPhoneLaunchpadApplicationsView: View {
    @Environment(VPhoneLaunchpadModel.self) private var platform
    private var model: VPhoneLaunchpadApplicationsModel { platform.applications }
    @State private var tab = 0
    @State private var localQuery = ""
    @State private var importFile = false
    @State private var installCandidate: VPhoneLocalApplication?
    @State private var downloadCandidate: VPhoneStoreApplication?
    private var machine: VPhoneLaunchpadMachine? {
        platform.machines.machines.first { $0.path.url.path == model.machinePath }
    }
    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("目标虚拟机", selection: $model.machinePath) {
                    Text("请选择").tag("")
                    ForEach(platform.machines.machines) { vm in
                        Text(vm.name + " — " + vm.path.libraryRoot).tag(vm.path.url.path)
                    }
                }
                Button("读取已安装") {
                    if let machine { Task { try? await model.refreshInstalled(machine) } }
                }.disabled(machine == nil || model.installedLoading)
            }.disabled(model.busy)
            if model.installedLoading { Text("正在读取目标机已安装版本…").font(.caption).foregroundStyle(.secondary) }
            if !model.installedError.isEmpty { Text(model.installedError).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            Picker("应用来源", selection: $tab) {
                Text("本地应用").tag(0); Text("ARM Store").tag(1)
            }.pickerStyle(.segmented)
            HStack {
                TextField(tab == 0 ? "筛选名称或 Bundle ID" : "搜索在线应用", text: tab == 0 ? $localQuery : $model.query)
                    .disabled(tab == 1 && model.busy)
                    .onSubmit { if tab == 1 { model.perform { try await model.search() } } }
                if tab == 0 {
                    Button("导入 IPA…") { importFile = true }.disabled(model.busy)
                    Button("刷新") {
                        model.perform {
                            try await model.refresh()
                            if let machine { try await model.refreshInstalled(machine) }
                        }
                    }.disabled(model.busy)
                } else {
                    TextField("地区", text: $model.country).frame(width: 55).disabled(model.busy)
                    Button("搜索") { model.perform { try await model.search() } }.disabled(model.busy)
                }
            }
            if tab == 0 {
                List(model.local.filter { localQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(localQuery) || $0.bundleID.localizedCaseInsensitiveContains(localQuery) }) { app in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(app.name + " · " + app.version)
                            Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                            Text(app.url.path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Spacer()
                        localAction(app)
                    }
                }
                Text("版本状态与本地安装包比较，不代表 ARM Store 当前最新版本。重新安装或降级可使用列表右侧菜单。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("ARM Store 会话")
                    Text(model.cookieFile.isEmpty ? "未配置" : URL(fileURLWithPath: model.cookieFile).lastPathComponent)
                    Button("选择私有文件…") { chooseSession() }.disabled(model.busy)
                }
                Text("复用有效登录会话；下载可能消耗账户额度。需登录或验证码时请在 ARM Store 正常完成。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("只显示目标机未安装的应用", isOn: $model.hideInstalled).disabled(!model.installedLoaded || model.busy)
                List(model.online.filter { !model.hideInstalled || model.installed[$0.bundleId] == nil }) { app in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(app.trackName + " · " + app.version)
                            Text(app.bundleId).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let installed = model.installed[app.bundleId] { Text("已安装 \(installed.version ?? "未知版本")").foregroundStyle(.secondary) }
                        Button("下载…") { downloadCandidate = app }.disabled(model.busy)
                    }
                }
            }
            if model.busy { ProgressView() }
            #if VPHONE_CUSTOM_TEMPORARY_INSTALL_MEMORY
            if model.memoryRecoveryPending {
                Button("恢复原内存并启动") { model.recoverInstallMemory(using: platform.machines) }
                    .disabled(model.busy)
            }
            #endif
            ScrollView {
                Text(model.status).font(.callout).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 110)
        }
        .padding().frame(minWidth: 800, minHeight: 560)
        .task { model.perform { try await model.refresh() } }
        .task(id: model.machinePath) {
            model.clearInstalled()
            if let machine { try? await model.refreshInstalled(machine) }
        }
        .onChange(of: machine.map { platform.machines.state(of: $0.path) }) { _, state in
            guard !model.busy else { return }
            if state == .running, let machine { Task { try? await model.refreshInstalled(machine) } }
            else if state == .stopped { model.clearInstalled() }
        }
        .fileImporter(isPresented: $importFile, allowedContentTypes: [.data]) { result in
            if case let .success(url) = result { model.perform { try await model.importPackage(url) } }
        }
        .alert("安装或替换应用？", isPresented: Binding(get: { installCandidate != nil }, set: { if !$0 { installCandidate = nil } })) {
            Button("取消", role: .cancel) { installCandidate = nil }
            Button("安装") {
                if let app = installCandidate, let machine { model.perform { try await model.install(app, machine: machine) } }
                installCandidate = nil
            }
        } message: {
            Text("目标：\(machine?.name ?? "")\n本地版本：\(installCandidate?.version ?? "")（构建 \(installCandidate?.build ?? "未知")）\n客体版本：\(installCandidate.flatMap { model.installed[$0.bundleID]?.version } ?? "未安装或未知")\n相同 Bundle ID 的应用将被替换；降级可能不兼容已有应用数据。")
        }
        #if VPHONE_CUSTOM_TEMPORARY_INSTALL_MEMORY
        .alert("临时使用 8 GB 重试安装？", isPresented: $model.showMemoryRetry) {
            Button("暂不重试", role: .cancel) { model.memoryRetry = nil }
            Button("确认增配并重试") { model.retryWithMemory(using: platform.machines) }
        } message: {
            Text("\(model.memoryRetry?.reason ?? "")\n\n目标：\(model.memoryRetry?.machine.name ?? "")\n资料库：\(model.memoryRetry?.machine.libraryRoot ?? "")\n将停机、临时调为 8 GB、启动并重试一次。无论结果如何，都会恢复原内存并启动。期间会增加 Mac 内存占用。超时不代表安装已停止，停机可能中断仍在进行的安装。关闭 Launchpad 会延后恢复至下次启动。不更换 Core。")
        }
        #endif
        .alert("从 ARM Store 下载？", isPresented: Binding(get: { downloadCandidate != nil }, set: { if !$0 { downloadCandidate = nil } })) {
            Button("取消", role: .cancel) { downloadCandidate = nil }
            if let machine {
                Button("下载并安装到 \(machine.name)") {
                    if let app = downloadCandidate { model.perform { try await model.downloadAndInstall(app, machine: machine) } }
                    downloadCandidate = nil
                }
            }
            Button("仅下载") {
                if let app = downloadCandidate { model.perform { try await model.download(app) } }
                downloadCandidate = nil
            }
        } message: { Text("可能消耗当前账户额度；安装会替换目标机上相同 Bundle ID 的应用，安装失败时仍保留已下载的包。") }
    }
    @ViewBuilder private func localAction(_ app: VPhoneLocalApplication) -> some View {
        if let installed = model.installed[app.bundleID], model.installedLoaded {
            VStack(alignment: .trailing) {
                Text("已安装 \(installed.version ?? "未知") · 构建 \(installed.build ?? "未知")")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    switch installed.compare(localVersion: app.version, localBuild: app.build) {
                    case .current: Text("已是最新版本").foregroundStyle(.secondary)
                    case .upgrade: Button("升级…") { installCandidate = app }.disabled(model.busy)
                    case .guestNewer: Text("虚拟机版本更高").foregroundStyle(.secondary)
                    case .unknown: Text("已安装，版本无法比较").foregroundStyle(.secondary)
                    }
                    Menu {
                        Button("使用此包重新安装／降级…") { installCandidate = app }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().disabled(model.busy)
                }
            }
        } else if model.installedLoaded {
            Button("安装…") { installCandidate = app }.disabled(machine == nil || model.busy)
        } else {
            Text(machine == nil ? "请选择目标虚拟机" : "等待读取安装状态").foregroundStyle(.secondary)
        }
    }
    private func chooseSession() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            model.cookieFile = url.path
            UserDefaults.standard.set(url.path, forKey: "applications.cookieFile")
        }
    }
}
#endif
