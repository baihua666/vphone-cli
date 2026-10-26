import Foundation
import VPhoneDistribution

/// Developer acceptance uses the same anonymous client and download path as Launchpad.
/// A new cache is mandatory so a previous local package cannot masquerade as a download.
func checkDownload(_ folder: URL) async throws {
    guard !FileManager.default.fileExists(atPath: folder.path) else {
        throw DistributionError("下载验收目录必须不存在，以保证真实网络下载")
    }
    guard let catalog = try await GitHubDistribution.fetch().first else {
        throw DistributionError("尚无已发布的发行目录")
    }
    let downloader = DistributionDownload(root: folder)
    let app = try await downloader.asset(catalog.app.asset, tag: catalog.tag)
    let core = try await downloader.asset(catalog.core.asset, tag: catalog.tag)
    try verifyArtifacts(dmg: app, core: core, baseline: catalog.app.baseline,
                        revision: catalog.app.revision, coreVersion: catalog.core.version,
                        signing: catalog.app.signingMode)
    print("真实下载验收通过：\(catalog.tag)；App \(catalog.app.asset.size) 字节、Core \(catalog.core.asset.size) 字节，SHA-256、签名与 Core seal 匹配。未安装 Core。")
}
