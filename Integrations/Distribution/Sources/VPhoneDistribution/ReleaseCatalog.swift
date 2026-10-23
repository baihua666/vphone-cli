import Foundation

public struct DistributionError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Immutable files within one GitHub release. No credentials or arbitrary download URLs.
public struct DistributionAsset: Codable, Sendable, Hashable {
    public let name: String
    public let size: Int64
    public let sha256: String
    public init(name: String, size: Int64, sha256: String) {
        self.name = name; self.size = size; self.sha256 = sha256
    }
    public func validate() throws {
        guard Self.safeName(name), size > 0, size < 2_147_483_648,
              sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            throw DistributionError("无效附件名称、大小或 SHA-256：\(name)")
        }
    }
    public static func safeName(_ name: String) -> Bool {
        name.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,119}$", options: .regularExpression) != nil
            && !name.contains("..")
    }
}

public enum DistributionSigning: String, Codable, Sendable { case notarized, internalDevelopment }

public struct DistributionApp: Codable, Sendable {
    public let baseline: String
    public let revision: Int
    public let signing: DistributionSigning?
    public var signingMode: DistributionSigning { signing ?? .notarized }
    public let minimumMacOS: Int
    public let asset: DistributionAsset
}
public struct DistributionCore: Codable, Sendable {
    /// The actual installed local seal identity, not the release tag.
    public let version: String
    public let asset: DistributionAsset
}
public struct DistributionImage: Codable, Sendable, Identifiable {
    public let id: String
    public let version: String
    public let revision: Int
    public let title: String
    public let coreVersion: String
    public let expandedBytes: Int64
    public let archiveBytes: Int64
    public let archiveSHA256: String
    public let parts: [DistributionAsset]
    public var cacheKey: String { "\(id)-\(revision)-\(archiveSHA256)" }
}
public struct DistributionCatalog: Codable, Sendable {
    public let previousTags: [String]?
    public let schema: Int
    public let tag: String
    public let app: DistributionApp
    public let core: DistributionCore
    public let images: [DistributionImage]
    public var assets: [DistributionAsset] { [app.asset, core.asset] + images.flatMap(\.parts) }

    public func validate() throws {
        guard schema == 1, DistributionAsset.safeName(tag), app.revision > 0,
              app.minimumMacOS >= 15, app.baseline.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil,
              core.version.hasPrefix(app.baseline + "-local."),
              core.version.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+-local\\.[a-f0-9]{8}$", options: .regularExpression) != nil,
              app.asset.name.hasSuffix(".dmg"), core.asset.name.hasSuffix(".zip"),
              assets.count < 1000, Set(assets.map(\.name)).count == assets.count, Set(images.map(\.id)).count == images.count else {
            throw DistributionError("发行目录不兼容或附件重复")
        }
        let history = previousTags ?? []
        guard history.count < 100, Set(history).count == history.count,
              !history.contains(tag), history.allSatisfy(DistributionAsset.safeName) else {
            throw DistributionError("历史发行 tag 无效")
        }
        try assets.forEach { try $0.validate() }
        for image in images {
            guard DistributionAsset.safeName(image.id), DistributionAsset.safeName(image.version),
                  !image.title.isEmpty, image.revision > 0, image.coreVersion == core.version,
                  image.expandedBytes > 0, image.expandedBytes < Int64.max / 8,
                  image.archiveBytes > 0, image.archiveBytes < Int64.max / 8,
                  !image.parts.isEmpty, image.parts.count <= 900,
                  image.archiveSHA256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
                throw DistributionError("镜像元数据无效：\(image.id)")
            }
            var total: Int64 = 0
            for part in image.parts {
                let sum = total.addingReportingOverflow(part.size)
                guard !sum.overflow else { throw DistributionError("镜像大小溢出") }
                total = sum.partialValue
            }
            guard total == image.archiveBytes else { throw DistributionError("镜像分片总大小不一致") }
        }
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 1_048_576 else { throw DistributionError("发行目录超过大小限制") }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        return value
    }
}
