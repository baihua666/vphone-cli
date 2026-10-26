#if VPHONE_CUSTOM_DISTRIBUTION
import AppKit
import Observation
import VPhoneDistribution

@MainActor @Observable
final class VPhoneLaunchpadAppUpdateModel {
    var catalog: DistributionCatalog?
    var status = "检查是否有可用的 Launchpad 更新。"
    var error = ""
    var busy = false
    var installing = false
    var canPause = false
    var fraction: Double = 0
    var installer: URL?
    private var task: Task<Void, Never>?
    private let fetch: @Sendable () async throws -> [DistributionCatalog]
    static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/vphone-launchpad/Distribution", isDirectory: true)
    let downloads = DistributionDownload(root: root.appendingPathComponent("Downloads", isDirectory: true))
    var currentRevision: Int { (Bundle.main.object(forInfoDictionaryKey: "VPhoneDistributionRevision") as? String).flatMap(Int.init) ?? 0 }
    var currentBaseline: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知" }
    var hasAppUpdate: Bool { catalog.map { $0.app.revision > currentRevision } ?? false }

    init(report: URL = root.appendingPathComponent("app-update-error.txt"),
         fetch: @escaping @Sendable () async throws -> [DistributionCatalog] = { try await GitHubDistribution.fetch() }) {
        self.fetch = fetch
        if let message = try? String(contentsOf: report, encoding: .utf8) {
            error = message
            try? FileManager.default.removeItem(at: report)
        }
    }

    func check() {
        run {
            self.catalog = nil
            self.status = "正在检查 App 更新…"
            self.catalog = try await self.fetch().first
            guard let catalog = self.catalog else {
                self.status = "尚无可用的 App 发行版本。"
                return
            }
            self.status = self.hasAppUpdate
                ? "有可用更新：\(catalog.app.baseline) · 修订 \(catalog.app.revision)"
                : "当前已是最新版本。"
        }
    }

    func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; error = ""; fraction = 0
        task = Task {
            defer { busy = false; canPause = false; task = nil }
            do { try await operation() }
            catch is CancellationError { status = "下载已暂停，点击更新可继续。" }
            catch {
                if Task.isCancelled { status = "下载已暂停，点击更新可继续。" }
                else { self.error = VPhoneLaunchpadError.message(for: error) }
            }
        }
    }

    func pause() { if canPause { task?.cancel() } }

    var progress: DistributionDownload.Progress {
        { [weak self] message, done, total in
            Task { @MainActor in
                self?.status = message
                self?.fraction = total > 0 ? Double(done) / Double(total) : 0
            }
        }
    }

    #if !VPHONE_CUSTOM_APP_UPDATE
    func downloadApp() {
        guard let catalog, hasAppUpdate else { return }
        run {
            guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= catalog.app.minimumMacOS else {
                throw DistributionError("此版本需要 macOS \(catalog.app.minimumMacOS) 或更新版本")
            }
            self.canPause = true
            self.installer = try await self.downloads.asset(catalog.app.asset, tag: catalog.tag, progress: self.progress)
            self.status = "App 安装包已校验。请正常停止实例并退出 Launchpad 后安装。"
        }
    }
    #endif
}
#endif
