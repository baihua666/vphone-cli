import SwiftUI
import VPhoneWSCore

/// One service serializes proxy writes across all Launchpad windows.
enum VPhoneLaunchpadProxyServices {
    static let proxy = ClashProxyService()
}

struct VPhoneLaunchpadDecodoView: View {
    let machine: VPhoneLaunchpadMachine
    let roots: [String]
    let isRunning: Bool
    @Environment(VPhoneLaunchpadModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var ispMode = true
    @State private var controller: DecodoProxyController?
    @State private var nativeController: NativeDecodoController?
    @State private var nativeSelected = false
    @State private var credentialsPath = DecodoLocalConfiguration.resolvedPath ?? DecodoLocalConfiguration.defaultPath

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("代理出口 · \(machine.name)").font(.headline)
            Picker("网络方案", selection: $nativeSelected) {
                Text("Clash · 现有方案").tag(false)
                Text("原生 HTTPS · 实验").tag(true)
            }.pickerStyle(.segmented)
                .disabled(nativeController?.busy == true || controller?.busy == true)
            if nativeSelected, let nativeController {
                VPhoneLaunchpadNativeProxyView(value: nativeController, catalog: controller, machine: machine, perform: perform)
            } else if let controller {
                if nativeController?.enabled == true {
                    Text("此实例正在使用原生出口，请先明确切回 Clash，再操作原有代理配置。")
                    Button("切回 Clash") { Task { await perform { await nativeController?.restoreClash() } } }
                        .disabled(nativeController?.busy == true)
                }
                form(controller)
                    .disabled(nativeController?.enabled == true || nativeController?.busy == true)
            } else {
                ProgressView()
            }
            HStack { Spacer(); Button("完成") { dismiss() }.disabled(controller?.busy == true || nativeController?.busy == true) }
        }
        .padding(20)
        .frame(width: 600, height: 650)
        .task {
            guard controller == nil else { return }
            let store = VPhoneLaunchpadBundleStore.root
            let client = VPhoneCLIClient(executable: store, libraryRoot: machine.path.libraryRoot,
                runner: SystemCLIRunner(), launchpadStore: store, isolationRoots: roots)
            let value = DecodoProxyController(client: client, proxy: VPhoneLaunchpadProxyServices.proxy, name: machine.name)
            let native = NativeDecodoController(client: client, name: machine.name)
            nativeController = native
            await native.refresh()
            nativeSelected = native.enabled
            controller = value
            await value.refresh()
            await value.syncLocations()
            if native.enabled { value.selectedLocation = native.configuredLocation(in: value.locations) }
            if value.route == nil && native.supported { nativeSelected = true }
            // No file is required when rotating an already configured session.
            if FileManager.default.fileExists(atPath: credentialsPath) {
                value.loadCredentials(path: credentialsPath)
            }
        }
    }

    private func perform(_ operation: () async -> Void) async {
        let network = VPhoneLaunchpadFlywheelNetwork.shared
        do {
            try await VPhoneLaunchpadFlywheelWebAction.shared.exclusively(on: machine.path) {
                network.invalidate(machine.path)
                await operation()
            }
            await network.check(machine, library: model.machines)
        } catch {
            // Another operation owns the result; do not invalidate or overwrite it.
        }
    }

    @ViewBuilder
    private func form(_ value: DecodoProxyController) -> some View {
        @Bindable var value = value
        Form {
            Picker("代理类型", selection: $ispMode) {
                Text("ISP · 按流量").tag(true)
                Text("动态住宅 · ZIP").tag(false)
            }.pickerStyle(.segmented)
            if ispMode {
                Section("ISP 出口") {
                    if let route = value.route {
                        LabeledContent("代理配置", value: route.selected)
                        LabeledContent("代理入口", value: route.endpoint ?? "未提供")
                    }
                    // Location discovery is account-scoped and remains available when routing needs repair.
                    VPhoneLaunchpadLocationPicker(value: value)
                    HStack {
                        Button("获取地区出口并检测") {
                            Task { await perform { await value.apply(rotate: false, cityISP: true) } }
                        }.disabled(!canRoute(value) || value.selectedLocation == nil)
                        Button("一键换 IP") {
                            Task { await perform { await value.apply(rotate: false, cityISP: true) } }
                        }.disabled(!canRoute(value) || value.selectedLocation == nil)
                    }
                    Button("刷新配置") { Task { await value.refresh() } }
                    Text("按选中地区申请 ISP 出口，每台实例使用独立新端口；供应商可能返回重复 IP。地区选择不保证邮编、街道距离或 App 的定位结果。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section("本机凭据") {
                    TextField("配置文件", text: $credentialsPath)
                    Button("读取文件") { value.loadCredentials(path: credentialsPath) }
                    TextField("原始代理用户名", text: $value.username)
                    SecureField("代理密码", text: $value.password)
                }
                Section("独立出口") {
                    TextField("美国 ZIP 邮编", text: $value.zip, prompt: Text("10001"))
                    if let route = value.route {
                        LabeledContent("代理配置", value: route.selected)
                        LabeledContent("代理入口", value: route.endpoint ?? "未提供")
                    }
                    if let session = value.session {
                        LabeledContent("会话", value: String(session.id.prefix(8)))
                        LabeledContent("已保存 ZIP", value: session.zip)
                    }
                    HStack {
                        Button("刷新配置") { Task { await value.refresh() } }
                        Button("保存、应用并检测") { Task { await perform { await value.apply(rotate: false) } } }
                            .disabled(!canApply(value) || value.username.isEmpty || value.password.isEmpty)
                        Button("换新 IP") { Task { await perform { await value.apply(rotate: true) } } }
                            .disabled(!canApply(value) || value.session == nil)
                    }
                }
            }
            Section("实测公网 IP") {
                Button("检测当前 IP") { Task { await perform { await value.detectCurrentIP() } } }
                    .disabled(!isRunning)
                Text("仅发起检测，不修改代理或断开连接；优先查询当前 Decodo 入口的 IPInfo 数据，再以 ipwho.is / ipwhois.app 对照。")
                    .font(.caption).foregroundStyle(.secondary)
                VPhoneLaunchpadCurrentIPView(path: machine.path)
                if value.egress != nil {
                    GroupBox("主要归属地 · Decodo / IPInfo") {
                        if let location = value.providerLocation { locationFields(location) }
                        Text(value.providerMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    GroupBox("第三方对照 · \(value.location?.source ?? "ipwho.is / ipwhois.app")") {
                        if let location = value.location { locationFields(location) }
                        Text(value.locationMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(value.locationComparison).font(.callout).textSelection(.enabled)
                } else {
                    Text("尚无检测结果；代理入口名称不代表实际公网 IP。").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(value.busy)
        if value.busy { ProgressView().controlSize(.small) }
        Text(value.message).font(.callout).textSelection(.enabled)
        if !isRunning { Text("请先启动此虚拟机，再应用或更换出口。").foregroundStyle(.secondary) }
        if !ispMode {
            Text("每台机器使用独立的五分钟 IP Lock 会话；点击换新会话才执行操作，不会定时断网。随机重复 IP 仍可能发生。ZIP 是区域筛选；此处验证 HTTPS/TCP 出口，不保证全部 App、DNS 或 UDP。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func locationFields(_ location: IPLocation) -> some View {
        LabeledContent("城市 / 地区", value: location.area)
        LabeledContent("邮编", value: location.postal.flatMap { $0.isEmpty ? nil : $0 } ?? "未知")
        LabeledContent("运营商", value: location.connection?.isp ?? "未知")
    }

    private func canRoute(_ value: DecodoProxyController) -> Bool {
        isRunning && machine.network.mode == "tunnel" && value.route != nil
    }

    private func canApply(_ value: DecodoProxyController) -> Bool {
        isRunning && machine.network.mode == "tunnel" && value.route != nil
            && value.zip.range(of: #"^[0-9]{5}$"#, options: .regularExpression) != nil
    }
}

struct VPhoneLaunchpadLocationPicker: View {
    @Bindable var value: DecodoProxyController
    @State private var locationSearch = ""
    @State private var locationKind: DecodoLocation.Kind?
    @State private var choosingLocation = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { choosingLocation = true } label: {
                HStack { Text("地点"); Spacer(); Text(value.selectedLocation?.label ?? "请选择官网地区"); Image(systemName: "chevron.down") }
            }
            .popover(isPresented: $choosingLocation) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("类型", selection: $locationKind) {
                        Text("全部").tag(nil as DecodoLocation.Kind?)
                        Text("国家").tag(DecodoLocation.Kind.country as DecodoLocation.Kind?)
                        Text("州").tag(DecodoLocation.Kind.state as DecodoLocation.Kind?)
                        Text("城市").tag(DecodoLocation.Kind.city as DecodoLocation.Kind?)
                    }.pickerStyle(.segmented)
                    TextField("搜索地点", text: $locationSearch)
                    let matches = DecodoLocation.filtered(value.locations, kind: locationKind, search: locationSearch)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if matches.isEmpty { Text("未找到地点").foregroundStyle(.secondary) }
                            ForEach([DecodoLocation.Kind.random, .country, .state, .city], id: \.self) { kind in
                                let rows = matches.filter { $0.kind == kind }
                                if !rows.isEmpty {
                                    if kind != .random && locationKind == nil {
                                        Text(kind == .country ? "国家" : kind == .state ? "州" : "城市").font(.caption).foregroundStyle(.secondary)
                                    }
                                    ForEach(rows) { location in
                                        Button {
                                            value.selectedLocation = location
                                            choosingLocation = false
                                        } label: {
                                            HStack { Text(location.label); Spacer(); if value.selectedLocation == location { Image(systemName: "checkmark") } }
                                                .frame(maxWidth: .infinity, alignment: .leading).padding(6).contentShape(Rectangle())
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 260)
                }.padding().frame(width: 360)
            }
            HStack {
                Button("同步官网地区") { Task { await value.syncLocations() } }
                Text(value.locationsMessage).font(.caption).foregroundStyle(.secondary)
            }
            SettingsLink { Text("Decodo 账号设置…") }

        }
    }

}
