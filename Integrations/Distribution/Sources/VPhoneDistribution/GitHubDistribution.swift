import Foundation
import CryptoKit

public enum GitHubDistribution {
    public static let repository = "baihua666/vphone-cli"
    public static let manifestName = "launchpad-catalog.json"

    public static func assetURL(tag: String, name: String) throws -> URL {
        guard DistributionAsset.safeName(tag), DistributionAsset.safeName(name) else {
            throw DistributionError("无效发行路径")
        }
        return URL(string: "https://github.com/\(repository)/releases/download/\(tag)/\(name)")!
    }

    public static let latestCatalogURL = URL(string: "https://github.com/\(repository)/releases/latest/download/\(manifestName)")!
    public typealias Fetch = @Sendable (URL) async throws -> (Data, Int)

    /// Release asset delivery does not consume the anonymous REST API quota.
    /// Trust comes from the fixed repository over HTTPS; asset hashes are checked
    /// on download. No GitHub token is shipped to clients.
    public static func fetch(load: Fetch = { url in
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("vphone-launchpad-distribution", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }) async throws -> [DistributionCatalog] {
        let (data, status) = try await load(latestCatalogURL)
        if status == 404 { return [] }
        guard status == 200 else { throw DistributionError("无法下载发行目录（HTTP \(status)），请稍后重试。此检查不使用 GitHub REST API。") }
        let latest = try DistributionCatalog.decode(data)
        var catalogs: [DistributionCatalog] = []
        // Re-read the immutable tag URL: the catalog must actually belong to
        // the tag it declares, rather than an unrelated latest release.
        for tag in [latest.tag] + (latest.previousTags ?? []) {
            let (content, code) = try await load(assetURL(tag: tag, name: manifestName))
            guard code == 200 else { throw DistributionError("发行目录下载失败：\(tag)（HTTP \(code)）") }
            let catalog = try DistributionCatalog.decode(content)
            guard catalog.tag == tag, tag != latest.tag || content == data else {
                throw DistributionError("目录与 Release tag 不一致，或最新目录已变化，请重试")
            }
            catalogs.append(catalog)
        }
        return try validatedVersions(catalogs)
    }
    static func validatedVersions(_ catalogs: [DistributionCatalog]) throws -> [DistributionCatalog] {
        // A mirror-only release may reuse the exact App build; the same App
        // revision with different bytes or compatibility metadata is forbidden.
        var appRevisions: [Int: String] = [:]
        for catalog in catalogs {
            let identity = "\(catalog.app.baseline):\(catalog.app.minimumMacOS):\(catalog.app.signingMode.rawValue):\(catalog.app.asset.sha256)"
            if let previous = appRevisions[catalog.app.revision], previous != identity {
                throw DistributionError("相同 App 发布修订的内容发生变化")
            }
            appRevisions[catalog.app.revision] = identity
        }
        var imageRevisions: [String: String] = [:]
        for image in catalogs.flatMap(\.images) {
            let key = "\(image.id):\(image.revision)"
            if let previous = imageRevisions[key], previous != image.archiveSHA256 {
                throw DistributionError("同一镜像版本内容发生变化：\(key)")
            }
            imageRevisions[key] = image.archiveSHA256
        }
        return catalogs.enumerated().sorted { left, right in
            left.element.app.revision == right.element.app.revision
                ? left.offset < right.offset : left.element.app.revision > right.element.app.revision
        }.map(\.element)
    }
}
extension Sequence where Element == UInt8 {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
