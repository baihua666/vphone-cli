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

    public func image(_ image: DistributionImage, tag: String, progress: Progress = { _, _, _ in }) async throws -> URL {
        guard !busy else { throw DistributionError("已有下载正在进行") }
        busy = true; defer { busy = false }
        try prepare()
        let output = root.appendingPathComponent(image.cacheKey + ".tzst")
        if try Self.matches(output, bytes: image.archiveBytes, digest: image.archiveSHA256) { return output }
        try Self.requireSpace(at: root, bytes: image.archiveBytes * 2)
        var pieces: [URL] = []
        var completed: Int64 = 0
        for part in image.parts {
            try Task.checkCancellation()
            progress("下载分片 \(pieces.count + 1)/\(image.parts.count)；已完成分片可续传", completed, image.archiveBytes)
            pieces.append(try await obtain(part, tag: tag, progress: { _, _, _ in }))
            completed += part.size
            progress("已校验分片 \(pieces.count)/\(image.parts.count)", completed, image.archiveBytes)
        }
        let partial = root.appendingPathComponent(UUID().uuidString + ".assembling")
        defer { try? FileManager.default.removeItem(at: partial) }
        FileManager.default.createFile(atPath: partial.path, contents: nil)
        let writer = try FileHandle(forWritingTo: partial)
        defer { try? writer.close() }
        var hash = SHA256()
        var written: Int64 = 0
        for piece in pieces {
            let reader = try FileHandle(forReadingFrom: piece)
            defer { try? reader.close() }
            while let data = try reader.read(upToCount: 1_048_576), !data.isEmpty {
                try Task.checkCancellation()
                try writer.write(contentsOf: data); hash.update(data: data); written += Int64(data.count)
                progress("合并并校验镜像", written, image.archiveBytes)
            }
        }
        try writer.synchronize()
        guard written == image.archiveBytes, hash.finalize().hex == image.archiveSHA256 else {
            throw DistributionError("完整镜像校验失败；保留分片以供重试")
        }
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        try FileManager.default.moveItem(at: partial, to: output)
        return output
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
        while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation(); hash.update(data: data)
        }
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
