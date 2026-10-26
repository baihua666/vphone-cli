import Foundation

public enum DistributionPublicationPolicy {
    public static func validate(_ catalog: DistributionCatalog, names: [String]) throws {
        guard catalog.images.isEmpty, (catalog.previousTags ?? []).isEmpty else {
            throw DistributionError("禁止发布镜像或引用历史镜像发行目录；镜像只能由本地目录管理。")
        }
        let allowed = Set([catalog.app.asset.name, catalog.core.asset.name,
                           GitHubDistribution.manifestName, "release-notes.md"])
        guard names.allSatisfy(allowed.contains) else {
            throw DistributionError("发布目录包含未允许的文件；只可上传 App、Core 和发行清单，禁止镜像及分片。")
        }
    }
}
