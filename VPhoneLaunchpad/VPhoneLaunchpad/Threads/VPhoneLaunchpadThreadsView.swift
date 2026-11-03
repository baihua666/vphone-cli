#if VPHONE_CUSTOM_THREADS_DESKTOP
import SwiftUI
import UniformTypeIdentifiers
import ThreadsDesktop

struct VPhoneLaunchpadThreadsView: View {
    @Environment(VPhoneLaunchpadModel.self) private var platform
    private var model: ThreadsDesktopModel { platform.threads }
    @State private var selectedAccount = ""
    @State private var username = ""
    @State private var password = ""
    @State private var machinePath = ""
    @State private var image: URL?
    @State private var caption = ""
    @State private var freshLogin = false
    @State private var testProfile = false
    @State private var chooseImage = false
    @State private var selectedTask: UUID?
    private var account: ThreadsAccount? { model.accounts.first { $0.id == selectedAccount } }
    private var record: ThreadsTaskRecord? { model.tasks.first { $0.id == selectedTask } }
    private var taskRequirement: String? {
        if model.running != nil { return "请等待当前任务结束" }
        if account == nil { return "请先添加并选择账号" }
        if image == nil && caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写文字或选择图片" }
        if caption.count > 500 { return "文案过长：最多 500 字" }
        return nil
    }
    private var executable: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/threads-automation") }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Threads 账号").font(.headline)
                    Spacer()
                    Button("添加账号", systemImage: "plus") {
                        selectedAccount = ""; username = ""; password = ""; machinePath = ""
                    }.disabled(model.running != nil)
                }
                Text(account == nil ? "添加账号" : "编辑账号").font(.subheadline)
                TextField("Instagram / Threads 用户名", text: $username)
                TextField("密码", text: $password)
                Picker("虚拟机", selection: $machinePath) {
                    Text("请选择").tag("")
                    ForEach(platform.machines.machines) { machine in
                        Text(machine.name).tag(machine.path.url.path)
                    }
                }
                Button(account == nil ? "添加并保存账号" : "保存账号修改") {
                    model.saveAccount(username: username, machinePath: machinePath, password: password)
                    if model.error.isEmpty {
                        selectedAccount = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        password = model.password(for: selectedAccount)
                    }
                }.disabled(model.running != nil || username.isEmpty || machinePath.isEmpty)
                if platform.machines.machines.isEmpty {
                    Text("尚无虚拟机，请先在主窗口创建或导入实例。").font(.caption).foregroundStyle(.orange)
                }
                Text("凭据独立保存在本机。使用 Threads 用户名；遇到验证码需在虚拟机完成后重试。").font(.caption).foregroundStyle(.secondary)
                Divider()
                if model.accounts.isEmpty { Text("还没有账号，请填写上方信息并添加。").foregroundStyle(.secondary) }
                List(model.accounts, selection: $selectedAccount) { account in
                    VStack(alignment: .leading) {
                        Text("@" + account.username)
                        Text(URL(fileURLWithPath: account.machinePath).lastPathComponent).font(.caption).foregroundStyle(.secondary)
                    }.tag(account.id)
                }.frame(minHeight: 100)
            }.padding().frame(minWidth: 240, idealWidth: 270, maxWidth: 320)
            ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("新建发帖任务").font(.headline)
                Text(account.map { "@\($0.username) · \(URL(fileURLWithPath: $0.machinePath).lastPathComponent)" } ?? "先选择账号")
                HStack {
                    Button("选择图片…") { chooseImage = true }
                    Text(image?.lastPathComponent ?? "图片可选；不选则发纯文字").lineLimit(1)
                    if image != nil { Button("移除图片") { image = nil } }
                }
                TextEditor(text: $caption).frame(height: 75).border(.separator)
                    .accessibilityLabel("发帖文案")
                HStack {
                    Toggle("强制退出并重新登录（仅测试）", isOn: $freshLogin)
                    Toggle("完整测试（简介修改后恢复）", isOn: $testProfile)
                }
                Text("默认核对当前账号并复用登录态；未登录时才登录。账号不匹配时停止并提示。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("只发布你填写的文字和选择的原图，不添加编号、水印或其它内容。任务编号仅用于本地记录。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("创建任务") {
                    if let account {
                        selectedTask = model.create(account: account, image: image, caption: caption,
                                                    freshLogin: freshLogin, testProfile: testProfile)
                    }
                }.disabled(taskRequirement != nil)
                if let taskRequirement {
                    Label(taskRequirement, systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Text("任务记录").font(.headline)
                List(model.tasks, selection: $selectedTask) { task in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("@\(task.request.account) · \(task.request.marker)")
                            Text(task.request.caption).font(.caption).lineLimit(1)
                        }
                        Spacer(); Text(task.status)
                    }.tag(task.id)
                }.frame(height: 150)
                if let record, let folder = model.directory(record.id) {
                    HStack(alignment: .top) {
                        if let preview = NSImage(contentsOf: folder.appendingPathComponent(record.request.imageName)) {
                            Image(nsImage: preview).resizable().scaledToFit().frame(width: 130, height: 130)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(record.request.publishedCaption).lineLimit(4).textSelection(.enabled)
                            Text(record.request.freshLogin ? "此任务：强制重新登录测试" : "此任务：优先复用当前登录态")
                                .font(.caption).foregroundStyle(.secondary)
                            if record.request.testProfile {
                                Text("此任务包含简介修改与恢复测试").font(.caption).foregroundStyle(.secondary)
                            }
                            Button(record.status == "待运行" ? "检查登录并发帖" : record.status == "已完成" ? "重试（已完成不重复发布）" : "重试同一任务") {
                                Task {
                                    await model.run(record.id, executable: executable) {
                                        try await platform.prepareThreadsMachine(socket: record.request.socket)
                                    }
                                }
                            }.disabled(model.running != nil)
                            Text("未启动时自动启动对应虚拟机，连接就绪后执行。重试沿用此任务保存的设置与发布状态；上方选项仅用于新建任务。").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if model.running != nil { ProgressView("正在执行，请勿同时操作目标虚拟机…") }
                ScrollView {
                    Text(model.running != nil ? model.progress : record?.detail ?? "")
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 100)
                if !model.error.isEmpty { Text(model.error).foregroundStyle(.red).textSelection(.enabled) }
            }.padding().frame(minWidth: 580)
            }
        }.frame(minWidth: 900, minHeight: 560)
        .onChange(of: selectedAccount) { _, _ in
            if let account {
                username = account.username; machinePath = account.machinePath
                password = model.password(for: account.username)
            }
        }
        .fileImporter(isPresented: $chooseImage, allowedContentTypes: [.image]) { result in
            switch result {
            case let .success(url): image = url
            case let .failure(error): model.error = error.localizedDescription
            }
        }
    }
}
@MainActor
private extension VPhoneLaunchpadModel {
    func prepareThreadsMachine(socket: String) async throws {
        await machines.refresh()
        guard let machine = machines.machines.first(where: { $0.path.url.path + "/vphone.sock" == socket }) else {
            throw ThreadsDesktopError("任务绑定的虚拟机已不存在，请核对实例。")
        }
        switch machines.state(of: machine.path) {
        case .stopped:
            machines.actionError = nil
            await machines.start(machine.path)
            if let failure = machines.actionError { throw failure }
        case let .busy(activity):
            throw ThreadsDesktopError("虚拟机正在执行其它操作：" + activity)
        case .running: break
        }
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            try Task.checkCancellation()
            if await Task.detached(operation: {
                VPhoneLaunchpadCreationPipeline.ping(socketPath: socket)
            }).value { return }
            guard machines.state(of: machine.path) == .running else {
                throw ThreadsDesktopError("虚拟机启动后已退出，请查看主窗口中该实例的运行日志。")
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw ThreadsDesktopError("等待虚拟机连接就绪超时（120 秒）。请确认虚拟机已进入桌面，再重试同一任务。连接：" + socket)
    }
}

#endif
