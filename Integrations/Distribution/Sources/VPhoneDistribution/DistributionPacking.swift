import Foundation
import CryptoKit

public enum DistributionPacking {
    /// Publishing only. Splits an immutable archive without loading it into memory.
    public static func split(_ source: URL, prefix: String, output: URL,
                             partBytes: Int = 1_073_741_824) throws -> (parts: [DistributionAsset], bytes: Int64, sha256: String) {
        guard DistributionAsset.safeName(prefix), partBytes > 0, partBytes < 2_147_483_648 else {
            throw DistributionError("分片参数无效")
        }
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        var whole = SHA256(); var total: Int64 = 0; var parts: [DistributionAsset] = []
        var done = false
        while !done {
            let name = String(format: "%@.part%04d", prefix, parts.count)
            let file = output.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: file.path) else { throw DistributionError("分片已存在，不覆盖") }
            FileManager.default.createFile(atPath: file.path, contents: nil)
            let writer = try FileHandle(forWritingTo: file)
            var size = 0; var hash = SHA256()
            do {
                while size < partBytes {
                    guard let data = try reader.read(upToCount: min(1_048_576, partBytes - size)), !data.isEmpty else { done = true; break }
                    try writer.write(contentsOf: data); size += data.count
                    hash.update(data: data); whole.update(data: data)
                }
                try writer.close()
            } catch { try? writer.close(); throw error }
            if size == 0 { try FileManager.default.removeItem(at: file); break }
            total += Int64(size)
            parts.append(DistributionAsset(name: name, size: Int64(size), sha256: hash.finalize().hex))
            guard parts.count <= 900 else { throw DistributionError("分片数量超过上限") }
        }
        guard total > 0 else { throw DistributionError("不能发布空镜像") }
        return (parts, total, whole.finalize().hex)
    }
}
