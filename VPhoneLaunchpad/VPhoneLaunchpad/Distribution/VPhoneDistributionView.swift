#if VPHONE_CUSTOM_DISTRIBUTION
import SwiftUI
import VPhoneDistribution

struct VPhoneDistributionView: View {
    @Environment(VPhoneLaunchpadModel.self) private var platform
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        @Bindable var distribution = platform.distribution
        VStack(alignment: .leading) {
            HStack {
                Text("开始使用与版本更新").font(.title2)
                Spacer()
                Button("检查更新") { distribution.check() }.disabled(distribution.busy)
                Button("稍后设置") {
                    UserDefaults.standard.set(true, forKey: "distribution.setupSeen")
                    NSApp.keyWindow?.close()
                }.disabled(distribution.busy)
            }.padding()
            Form {
                Section("1 · 主机准备") {
                    LabeledContent("当前主机", value: platform.host.requiredPassed ? "检查通过" : "需要完成设置")
                    Text("需要实体 Apple Silicon Mac。首次可能需要管理员认证或在恢复模式调整 Research Guests 设置；重启后可继续。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("打开主机设置") { openWindow(id: "main"); platform.present(.hostSetup) }
                }
                Section("2 · App 与 Core 版本") {
                    Text(distribution.appStatus)
                    Picker("发行版本", selection: $distribution.selectedTag) {
                        Text("请选择").tag("")
                        ForEach(distribution.catalogs, id: \.tag) { catalog in
                            Text("\(catalog.tag) · App 修订 \(catalog.app.revision)").tag(catalog.tag)
                        }
                    }.disabled(distribution.busy)
                    if let catalog = distribution.selected {
                        if catalog.app.signingMode == .internalDevelopment {
                            Text("内部开发签名版（未公证）：首次打开可能需要在系统设置中允许；Helper 仍需管理员认证。").font(.caption).foregroundStyle(.secondary)
                        }
                        LabeledContent("官方基线", value: catalog.app.baseline)
                        LabeledContent("匹配 Core", value: catalog.core.version)
                        HStack {
                            Button("下载 App 更新安装包") { distribution.downloadApp() }.disabled(distribution.busy)
                            Button("安装匹配 Core") { distribution.installCore(using: platform) }
                                .disabled(distribution.busy || !platform.canInstallBundles || platform.bundles.isUsable(catalog.core.version))
                        }
                    }
                    if let installer = distribution.installer {
                        Button("在 Finder 中显示安装包") { NSWorkspace.shared.activateFileViewerSelecting([installer]) }
                        Text("安装前正常停止实例并退出 Launchpad，保留旧 app。此操作不会自动替换运行中的程序。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("3 · 镜像版本库与创建实例") {
                    Picker("镜像版本（全部发行版）", selection: $distribution.selectedImageID) {
                        Text("请选择").tag("")
                        ForEach(distribution.imageVersions) { version in
                            Text("\(version.image.title) · \(version.image.version)（修订 \(version.image.revision)）").tag(version.id)
                        }
                    }.disabled(distribution.busy)
                    if !distribution.catalogs.isEmpty && distribution.imageVersions.isEmpty {
                        Text("尚未发布镜像。可在主窗口通过“＋”从固件新建或导入已有镜像；发布镜像后点击“检查更新”即可显示。")
                    }
                    if let image = distribution.image {
                        LabeledContent("所需 Core", value: image.coreVersion)
                        LabeledContent("Core 状态", value: platform.bundles.isUsable(image.coreVersion) ? "已就绪" : "创建时自动下载并安装，可能需要管理员认证")
                        LabeledContent("镜像来源", value: distribution.imageVersion?.catalog.tag ?? "")
                        LabeledContent("导入所需可用空间", value: ByteCountFormatter.string(fromByteCount: image.expandedBytes * 2 + 1_073_741_824, countStyle: .file))
                        LabeledContent("下载大小", value: ByteCountFormatter.string(fromByteCount: image.archiveBytes, countStyle: .file))
                        LabeledContent("目标资料库", value: platform.machines.libraryRoot)
                        TextField("新实例名称", text: $distribution.machineName).disabled(distribution.busy)
                        Text("使用新设备身份；模板更新只创建新实例，不升级或覆盖已有实例的磁盘。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("仅下载／继续下载") { distribution.downloadImage() }.disabled(distribution.busy)
                            Button("创建并启动新虚拟机") { distribution.installImage(using: platform) }
                                .disabled(distribution.busy || !platform.host.requiredPassed || (!platform.bundles.isUsable(image.coreVersion) && !platform.canInstallBundles) || distribution.machineName.isEmpty)
                        }
                    }
                    if !platform.host.requiredPassed {
                        Text("请先完成第 1 步主机设置；完成后可继续，无需手动安装 Core。").font(.caption).foregroundStyle(.secondary)
                    } else if let image = distribution.image, !platform.bundles.isUsable(image.coreVersion), !platform.canInstallBundles {
                        Text("请在主机设置中完成 Helper 和开发者工具授权，才能自动安装 Core。").font(.caption).foregroundStyle(.secondary)
                    }
                    if distribution.createdMachine != nil {
                        Button("重试启动已导入实例") { distribution.retryStart(using: platform) }.disabled(distribution.busy)
                    }
                }
                if !distribution.receipts.isEmpty {
                    Section("已创建实例的模板版本") {
                        ForEach(distribution.receipts) { receipt in
                            let newer = distribution.catalogs.flatMap(\.images).filter { receipt.updateAvailable($0) }.max { $0.revision < $1.revision }
                            VStack(alignment: .leading) {
                                Text("\(receipt.imageID) · \(receipt.imageVersion)")
                                Text(receipt.machinePath).font(.caption).textSelection(.enabled)
                                Text(newer.map { "有新模板 \($0.version)，可在镜像版本库选择并创建新实例" } ?? "未发现更新模板（这是导入记录，不代表当前客体系统版本）")
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
}
#endif
