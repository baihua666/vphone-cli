import Foundation
import CryptoKit

/// A cancelled download keeps verified complete chunks; the current chunk is retried.
/// Memory stays bounded while hashing/assembling multi-gigabyte archives.
public actor DistributionDownload {
    public typealias Progress = @Sendable (String, Int64, Int64) -> Void
    public typealias Fetch = @Sendable (URL) async throws -> URL
    private let root: URL
    private let fetch: Fetch
    private var busy = false

    public init(root: URL, fetch: @escaping Fetch = { url in
        let (file, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            try? FileManager.default.removeItem(at: file)
            throw DistributionError("下载失败，请检查网络后重试")
        }
        return file
    }) { self.root = root; self.fetch = fetch }

    public func asset(_ asset: DistributionAsset, tag: String, progress: Progress = { _, _, _ in }) async throws -> URL {
        guard !busy else { throw DistributionError("已有下载正在进行") }
        busy = true; defer { busy = false }
        try asset.validate()
        try prepare()
        return try await obtain(asset, tag: tag, progress: progress)
    }

    public func image(_ image: DistributionImage, tag: String, localArchive: URL? = nil,
                      progress: Progress = { _, _, _ in }) async throws -> URL {
        guard !busy else { throw DistributionError("已有下载正在进行") }
        busy = true; defer { busy = false }
        if let localArchive {
            guard localArchive.isFileURL,
                  try Self.matches(localArchive, bytes: image.archiveBytes, digest: image.archiveSHA256) else {
                throw DistributionError("本地镜像不存在或大小／SHA-256 与所选镜像版本不一致。请选择匹配的完整归档；不会自动改为下载。")
            }
            try Task.checkCancellation()
            return localArchive
        }
        throw DistributionError("镜像在线下载已停用，请从本地镜像目录选择完整归档。")
    }

    private func prepare() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    private func obtain(_ asset: DistributionAsset, tag: String, progress: Progress) async throws -> URL {
        try Task.checkCancellation()
        try asset.validate()
        let target = root.appendingPathComponent(asset.sha256 + "-" + asset.name)
        if try Self.matches(target, bytes: asset.size, digest: asset.sha256) { return target }
        try Self.requireSpace(at: root, bytes: asset.size)
        progress("下载 \(asset.name)", 0, asset.size)
        let file = try await fetch(GitHubDistribution.assetURL(tag: tag, name: asset.name))
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        guard try Self.matches(file, bytes: asset.size, digest: asset.sha256) else {
            throw DistributionError("附件大小或 SHA-256 校验失败：\(asset.name)")
        }
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.moveItem(at: file, to: target)
        progress("下载校验完成", asset.size, asset.size)
        return target
    }

    public static func digest(_ file: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        var hash = SHA256()
        // Foundation's FileHandle buffers are autoreleased on macOS. Drain per
        // chunk so synchronous multi-GB work cannot retain the whole archive.
        while try autoreleasepool(invoking: {
            guard let data = try input.read(upToCount: 1_048_576), !data.isEmpty else { return false }
            try Task.checkCancellation(); hash.update(data: data)
            return true
        }) {}
        return hash.finalize().hex
    }
    public static func matches(_ file: URL, bytes: Int64, digest: String) throws -> Bool {
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, Int64(values.fileSize ?? -1) == bytes else { return false }
        return try Self.digest(file) == digest
    }
    public static func requireSpace(at folder: URL, bytes: Int64) throws {
        let values = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard bytes >= 0, let free = values.volumeAvailableCapacityForImportantUsage, free >= bytes + 1_073_741_824 else {
            throw DistributionError("可用磁盘空间不足，需为下载、合并和解压预留空间")
        }
    }
}
