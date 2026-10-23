#if VPHONE_CUSTOM_DISTRIBUTION
import AppKit
import Foundation
import Observation
import VPhoneDistribution

@MainActor @Observable
final class VPhoneDistributionModel {
    var catalogs: [DistributionCatalog] = []
    var selectedTag = ""
    var selectedImageID = ""
    var machineName = "my-iphone"
    var status = "点击检查版本，读取本项目的 GitHub Releases。"
    var error = ""
    var fraction: Double = 0
    var busy = false
    var canPause = false
    var installer: URL?
    var receipts: [DistributionReceipt] = []
    var receiptError = ""
    var createdMachine: VPhoneLaunchpadMachinePath?
    private var task: Task<Void, Never>?
    static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/vphone-launchpad/Distribution", isDirectory: true)
    private let downloads = DistributionDownload(root: root.appendingPathComponent("Downloads", isDirectory: true))
    private var receiptFile: URL { Self.root.appendingPathComponent("images.json") }
    var selected: DistributionCatalog? { catalogs.first { $0.tag == selectedTag } }
    var image: DistributionImage? { selected?.images.first { $0.id == selectedImageID } }
    var currentRevision: Int { (Bundle.main.object(forInfoDictionaryKey: "VPhoneDistributionRevision") as? String).flatMap(Int.init) ?? 0 }
    var appStatus: String {
        guard let latest = catalogs.first else { return "尚未获取发行版本" }
        if currentRevision == 0 { return "当前为开发构建；最新发布修订 \(latest.app.revision)" }
        return latest.app.revision > currentRevision ? "有更新：修订 \(currentRevision) → \(latest.app.revision)" : "当前修订 \(currentRevision)，未发现更新"
    }
    init() {
        guard FileManager.default.fileExists(atPath: receiptFile.path) else { return }
        do { receipts = try JSONDecoder().decode([DistributionReceipt].self, from: Data(contentsOf: receiptFile)) }
        catch { receiptError = "镜像安装记录无法读取，原文件保留：\(error.localizedDescription)" }
    }
    func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; error = ""; fraction = 0
        task = Task {
            defer { busy = false; canPause = false; task = nil }
            do { try await operation() }
            catch is CancellationError { status = "已暂停；已校验分片保留，重新下载可继续。" }
            catch {
                if Task.isCancelled { status = "已暂停；已校验分片保留，重新下载可继续。" }
                else { self.error = VPhoneLaunchpadError.message(for: error) }
            }
        }
    }
    func pause() { if canPause { task?.cancel() } }
    func check() {
        run {
            self.status = "检查 App、Core 与镜像版本…"
            let catalogs = try await GitHubDistribution.fetch()
            self.catalogs = catalogs
            self.selectedTag = catalogs.first?.tag ?? ""
            self.selectedImageID = catalogs.first?.images.first?.id ?? ""
            self.status = catalogs.isEmpty ? "尚无可用发行目录；发布工具上传正式 Release 后即可使用。" : "版本目录已更新；仅检查，不会替换 App、Core 或实例。"
        }
    }
    private var progress: DistributionDownload.Progress {
        { [weak self] message, done, total in
            Task { @MainActor in
                self?.status = message
                self?.fraction = total > 0 ? Double(done) / Double(total) : 0
            }
        }
    }
    func downloadApp() {
        guard let catalog = selected else { return }
        run {
            guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= catalog.app.minimumMacOS else {
                throw DistributionError("此版本需要 macOS \(catalog.app.minimumMacOS) 或更新版本")
            }
            self.canPause = true
            self.installer = try await self.downloads.asset(catalog.app.asset, tag: catalog.tag, progress: self.progress)
            self.status = "App 安装包已校验。请先正常停止实例并退出 Launchpad，保留旧 app 后安装更新。"
        }
    }
    func installCore(using model: VPhoneLaunchpadModel) {
        guard let catalog = selected else { return }
        run {
            guard model.canInstallBundles else { throw DistributionError("请先完成主机设置、Helper 和开发者工具授权") }
            self.canPause = true
            let zip = try await self.downloads.asset(catalog.core.asset, tag: catalog.tag, progress: self.progress)
            try Task.checkCancellation()
            self.canPause = false
            self.status = "安装匹配的 Core，保留现有默认值与实例绑定…"
            let candidate = try await VPhoneLaunchpadLocalBundle.prepare(zip)
            defer { try? FileManager.default.removeItem(at: candidate.workDirectory) }
            guard candidate.version == catalog.core.version else { throw DistributionError("下载的 Core seal 与发行目录不一致，未安装") }
            await model.installLocalBundle(zip, keepsDefault: model.bundles.defaultVersion != nil)
            guard model.bundles.isUsable(catalog.core.version) else {
                throw model.bundles.progress?.error ?? VPhoneLaunchpadError("Core 内容身份不匹配或主机验证未通过")
            }
            self.status = "Core 已就绪：\(catalog.core.version)；原有实例未换绑。"
        }
    }
    func downloadImage() {
        guard let image, let catalog = selected else { return }
        run {
            self.canPause = true
            _ = try await self.downloads.image(image, tag: catalog.tag, progress: self.progress)
            self.status = "镜像 \(image.title) \(image.version) 下载并校验完成；已有实例保持不变。"
        }
    }
    func installImage(using model: VPhoneLaunchpadModel) {
        guard let image, let catalog = selected else { return }
        let name = machineName
        run {
            guard self.receiptError.isEmpty else { throw DistributionError(self.receiptError) }
            guard model.host.requiredPassed, model.bundles.isUsable(image.coreVersion),
                  let cli = model.bundles.commandLine(version: image.coreVersion) else {
                throw DistributionError("请先完成主机检查并安装该镜像匹配的 Core")
            }
            let root = model.machines.libraryRoot
            if let issue = VPhoneLaunchpadMachineLocations.problem(with: root) { throw DistributionError(issue) }
            guard DistributionAsset.safeName(name), VPhoneLaunchpadMachineLocations.socketPathFits(root: root, name: name) else {
                throw DistributionError("实例名无效或路径过长")
            }
            let path = VPhoneLaunchpadMachinePath(libraryRoot: root, name: name)
            guard !FileManager.default.fileExists(atPath: path.url.path) else { throw DistributionError("实例名称已存在，请使用新名称") }
            let folder = URL(fileURLWithPath: root, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try DistributionDownload.requireSpace(at: folder, bytes: image.expandedBytes * 2)
            self.canPause = true
            let archive = try await self.downloads.image(image, tag: catalog.tag, progress: self.progress)
            try Task.checkCancellation()
            self.canPause = false
            self.status = "导入并创建独立身份，请勿退出 Launchpad…"
            try DistributionDownload.requireSpace(at: folder, bytes: image.expandedBytes * 2)
            _ = try await ImageInstallation.prepare(archive: archive, library: folder, name: name, finalize: { ready in
                let staged = VPhoneLaunchpadMachinePath(libraryRoot: ready.deletingLastPathComponent().path, name: ready.lastPathComponent)
                try VPhoneLaunchpadMachineBinding(bundle: image.coreVersion).save(to: staged)
            }) { arguments in
                try await cli.runChecked(arguments)
            }
            self.createdMachine = path
            // Keep the authoritative binding format; provenance stays in our own receipt.
            try model.machines.bind(path, VPhoneLaunchpadMachineBinding(bundle: image.coreVersion))
            self.receipts.append(DistributionReceipt(image: image, machinePath: path.url.path))
            try FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
            do { try JSONEncoder().encode(self.receipts).write(to: self.receiptFile, options: .atomic) }
            catch { self.receiptError = "实例已导入但安装记录保存失败：\(error.localizedDescription)"; throw error }
            await model.machines.refresh()
            self.status = "实例已导入，正在启动…"
            try await self.start(path, using: model)
            self.status = "\(name) 已启动且客体就绪；镜像版本 \(image.version)。"
            UserDefaults.standard.set(true, forKey: "distribution.setupSeen")
        }
    }
    func retryStart(using model: VPhoneLaunchpadModel) {
        guard let path = createdMachine else { return }
        run { try await self.start(path, using: model); self.status = "\(path.name) 客体已就绪" }
    }
    private func start(_ path: VPhoneLaunchpadMachinePath, using model: VPhoneLaunchpadModel) async throws {
        model.machines.actionError = nil
        if model.machines.state(of: path) == .stopped { await model.machines.start(path) }
        if let error = model.machines.actionError { throw error }
        for _ in 0..<120 {
            try Task.checkCancellation()
            if model.machines.panicked.contains(path) { throw DistributionError("客体启动发生内核异常，请查看实例日志") }
            if await Task.detached(operation: { VPhoneLaunchpadCreationPipeline.ping(socketPath: path.url.appendingPathComponent("vphone.sock").path) }).value { return }
            try await Task.sleep(for: .seconds(1))
        }
        throw DistributionError("实例已保留，但启动 120 秒内未确认就绪。请在平台检查后重试启动，无需再次导入。")
    }
}
#endif
