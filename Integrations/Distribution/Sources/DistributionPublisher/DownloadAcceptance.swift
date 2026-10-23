import Foundation
import VPhoneDistribution

/// Developer acceptance uses the same anonymous client and download path as Launchpad.
/// A new cache is mandatory so a previous local package cannot masquerade as a download.
func checkDownload(_ folder: URL, includeImages: Bool = false) async throws {
    guard !FileManager.default.fileExists(atPath: folder.path) else {
        throw DistributionError("下载验收目录必须不存在，以保证真实网络下载")
    }
    guard let catalog = try await GitHubDistribution.fetch().first else {
        throw DistributionError("尚无已发布的发行目录")
    }
    if includeImages && catalog.images.isEmpty {
        throw DistributionError("发行目录没有镜像，不能通过完整镜像下载验收")
    }
    let downloader = DistributionDownload(root: folder)
    let app = try await downloader.asset(catalog.app.asset, tag: catalog.tag)
    let core = try await downloader.asset(catalog.core.asset, tag: catalog.tag)
    try verifyArtifacts(dmg: app, core: core, baseline: catalog.app.baseline,
                        revision: catalog.app.revision, coreVersion: catalog.core.version,
                        signing: catalog.app.signingMode)
    if includeImages {
        for image in catalog.images {
            _ = try await downloader.image(image, tag: catalog.tag)
            print("镜像下载与合并校验通过：\(image.id) / \(image.version)，\(image.parts.count) 个分片，\(image.archiveBytes) 字节。尚未导入或启动。")
        }
    }
    print("真实下载验收通过：\(catalog.tag)；App \(catalog.app.asset.size) 字节、Core \(catalog.core.asset.size) 字节，SHA-256、签名与 Core seal 匹配。未安装 Core。")
}
