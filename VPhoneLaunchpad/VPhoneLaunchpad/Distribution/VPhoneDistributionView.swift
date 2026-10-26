#if VPHONE_CUSTOM_DISTRIBUTION
import SwiftUI
import VPhoneDistribution

struct VPhoneDistributionView: View {
    @Environment(VPhoneLaunchpadModel.self) private var platform
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    private var distribution: VPhoneDistributionModel { platform.distribution }
    private var permissionsReady: Bool { platform.host.requiredPassed }
    private var coreReady: Bool { distribution.stepState(.core, using: platform) == .completed }

    var body: some View {
        @Bindable var distribution = distribution
        VStack(alignment: .leading) {
            HStack {
                Text("开始使用与版本更新").font(.title2)
                Spacer()
                #if VPHONE_CUSTOM_APP_UPDATE
                if distribution.hasAppUpdate {
                    Button(distribution.updatingApp ? "更新中…" : "更新") { distribution.updateApp(using: platform) }
                        .buttonStyle(.borderedProminent).disabled(distribution.busy)
                }
                #endif
                Button("检查更新／重试") { distribution.check() }.disabled(distribution.busy)
                Button("关闭") {
                    UserDefaults.standard.set(true, forKey: "distribution.setupSeen")
                    dismissWindow(id: "distribution")
                }.keyboardShortcut(.cancelAction)
            }.padding()
            Form {
                Section {
                    let completed = [DistributionSetupProgress.Step.permissions, .core, .image, .launch]
                        .filter { distribution.stepState($0, using: platform) == .completed }.count
                    Text("准备进度：\(completed) / 4 步已完成").font(.headline)
                    Text("安装主 APP 后可在线安装 Core；镜像仅从本地目录选择，不上传或在线下载镜像。")
                    Text("需要实体 Apple Silicon Mac、本机 APFS 资料库和管理员权限。镜像与版本清单由本地目录管理；导入空间以所选镜像为准。")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("完整安装说明", destination: URL(string: "https://github.com/baihua666/vphone-cli/blob/tb_dev/Documents/Guides/launchpad-internal-user-guide.md")!)
                }
                Section {
                    stepStatus(.permissions)
                    Text("打开主机设置，允许开发者工具访问，并按提示安装 Helper；管理员密码只输入 macOS 系统弹窗。返回后点击重新检查。")
                    Text("未公证内部版的首次打开许可需在系统设置中确认。若 Core 检查要求 Research Guests 设置，需在恢复模式操作，重启后回到此处继续；APP 不能代替系统授权。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("打开主机设置") { openWindow(id: "main"); platform.present(.hostSetup) }
                        Button("重新检查权限") { distribution.recheckPermissions(using: platform) }
                            .disabled(distribution.busy || platform.host.isChecking)
                    }
                    Text("主机检查：\(platform.host.passedCount) / \(platform.host.checks.count) 项已满足")
                        .font(.caption)
                } header: { Text("1 · 权限设置") }
                Section {
                    stepStatus(.core)
                    Picker("发行版本", selection: $distribution.selectedTag) {
                        Text("请选择").tag("")
                        ForEach(distribution.catalogs, id: \.tag) { catalog in
                            Text("\(catalog.tag) · App 修订 \(catalog.app.revision)").tag(catalog.tag)
                        }
                    }.disabled(distribution.busy)
                    if let image = distribution.image, coreReady {
                        LabeledContent("匹配 Core", value: image.coreVersion)
                        Text("所需 Core 已安装，可使用本地镜像。")
                    } else if let catalog = distribution.setupCatalog {
                        LabeledContent("匹配 Core", value: catalog.core.version)
                        Text("Core 是运行组件，不是 iPhone 镜像。点击下方按钮后自动下载、校验并通过 Helper 安装；不会改绑已有实例。")
                        Button(coreReady ? "Core 已就绪" : "安装匹配 Core／重试") {
                            distribution.installCore(using: platform)
                        }.disabled(distribution.busy || !permissionsReady || !platform.canInstallBundles || coreReady)
                    } else {
                        Text("请先点击窗口顶部的“检查更新／重试”获取发行目录。")
                    }
                    if !permissionsReady { Text("请先完成第 1 步权限设置。").foregroundStyle(.secondary) }
                } header: { Text("2 · Core 安装") }
                Section {
                    #if VPHONE_CUSTOM_LOCAL_IMAGES
                    HStack {
                        Button("选择镜像目录…") { distribution.chooseLocalImageDirectory() }
                        Button("刷新本地目录") { distribution.reloadLocalImages() }
                            .disabled(distribution.localImageDirectory.isEmpty)
                    }.disabled(distribution.busy)
                    Text(distribution.localImageDirectory.isEmpty ? "尚未选择目录" : distribution.localImageDirectory)
                        .font(.caption).textSelection(.enabled)
                    Picker("本地镜像版本", selection: $distribution.selectedImageID) {
                        Text("请选择").tag("")
                        ForEach(distribution.imageVersions) { item in
                            Text("\(item.image.title) · \(item.image.version)（修订 \(item.image.revision)）").tag(item.id)
                        }
                    }.disabled(distribution.busy)
                    if let image = distribution.image {
                        LabeledContent("所需 Core", value: image.coreVersion)
                        LabeledContent("本地归档", value: ByteCountFormatter.string(fromByteCount: image.archiveBytes, countStyle: .file))
                        LabeledContent("导入所需可用空间", value: ByteCountFormatter.string(fromByteCount: image.expandedBytes * 2 + 1_073_741_824, countStyle: .file))
                        Button("校验本地镜像") { distribution.downloadImage() }.disabled(distribution.busy)
                    }
                    Text("镜像仅在线下管理。目录内放置完整归档和 images.json 版本清单；更新文件后刷新目录。创建前核对大小与 SHA-256，不上传、不复制到下载缓存、不覆盖已有实例。自有归档也可从主窗口“文件 → 导入…”使用。")
                        .font(.caption).foregroundStyle(.secondary)
                    #else
                    Text("镜像在线下载已停用。请从主窗口“文件 → 导入…”使用本地镜像。")
                    #endif
                    stepStatus(.image)
                } header: { Text("3 · 本地镜像目录") }
                Section {
                    stepStatus(.launch)
                    LabeledContent("目标资料库", value: platform.machines.libraryRoot)
                    TextField("新实例名称", text: $distribution.machineName).disabled(distribution.busy)
                    Text("名称只用英文字母、数字、点、横线或下划线，且不能与现有实例重名。创建时使用新设备身份，不覆盖已有磁盘。")
                        .font(.caption).foregroundStyle(.secondary)
                    if distribution.importedMachine(using: platform) != nil {
                        Text("当前实例已导入。可直接启动并检查客体，不需要重复导入。")
                        Button("重试启动已导入实例") { distribution.retryStart(using: platform) }
                            .disabled(distribution.busy || !permissionsReady || !coreReady)
                    } else {
                        Text("准备好镜像后点击创建；也可直接点击下方按钮，APP 会校验本地镜像，再导入并启动。等待显示“已启动且客体就绪”后，检查 iPhone 桌面及网络。")
                        Button("创建并启动新虚拟机") { distribution.installImage(using: platform) }
                            .disabled(distribution.busy || !permissionsReady || !coreReady || distribution.image == nil || distribution.machineName.isEmpty)
                    }
                    Text("导入期间请勿退出 APP、拔盘或让 Mac 休眠。完成后可在主列表正常启动、停止实例。重开 APP 后，请从主列表启动已创建的实例；本步完成表示本次已通过启动检查，不代表实例会始终运行。")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("4 · 创建启动") }
                Section("后续 App 更新") {
                    Text(distribution.appStatus)
                    #if VPHONE_CUSTOM_APP_UPDATE
                    Text("更新将自动下载、校验、安装并重启 Launchpad。请先停止虚拟机；Core、镜像和实例绑定保持不变。")
                        .font(.caption).foregroundStyle(.secondary)
                    #else
                    Text("内部开发签名版未公证。安装更新前先停止实例并退出 APP；更新包不会自动替换正在运行的程序。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("下载 App 更新安装包") { distribution.downloadApp() }
                        .disabled(distribution.busy || distribution.selected == nil)
                    if let installer = distribution.installer {
                        Button("在 Finder 中显示安装包") { NSWorkspace.shared.activateFileViewerSelecting([installer]) }
                    }
                    #endif
                }
                if !distribution.receipts.isEmpty {
                    Section("已创建实例的模板版本") {
                        ForEach(distribution.receipts) { receipt in
                            let newer = distribution.imageVersions.map(\.image).filter { receipt.updateAvailable($0) }.max { $0.revision < $1.revision }
                            VStack(alignment: .leading) {
                                Text("\(receipt.imageID) · \(receipt.imageVersion)")
                                Text(receipt.machinePath).font(.caption).textSelection(.enabled)
                                Text(newer.map { "有新模板 \($0.version)，可选择并创建新实例" } ?? "未发现更新模板（本地导入记录，不代表当前客体系统版本）")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }.formStyle(.grouped)
            VStack(alignment: .leading) {
                if distribution.busy { ProgressView(value: distribution.fraction) }
                Text(distribution.status).textSelection(.enabled)
                if !distribution.error.isEmpty { Text(distribution.error).foregroundStyle(.red).textSelection(.enabled) }
                if !distribution.receiptError.isEmpty { Text(distribution.receiptError).foregroundStyle(.red).textSelection(.enabled) }
                if distribution.canPause { Button("暂停下载") { distribution.pause() } }
            }.padding()
        }
        .frame(minWidth: 720, minHeight: 650)
        .task { if distribution.catalogs.isEmpty && !distribution.busy { distribution.check() } }
    }

    @ViewBuilder private func stepStatus(_ step: DistributionSetupProgress.Step) -> some View {
        switch distribution.stepState(step, using: platform) {
        case .pending: Label("未完成", systemImage: "circle").foregroundStyle(.secondary)
        case .running: Label("进行中", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.blue)
        case .completed: Label("已完成", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .paused: Label("已暂停，可继续", systemImage: "pause.circle").foregroundStyle(.orange)
        case let .failed(message):
            Label("失败，可重试", systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
            Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled)
        }
    }
}
#endif
