import Foundation

public struct DistributionLocalImage: Identifiable, Sendable {
    public let image: DistributionImage
    public let archive: URL
    public var id: String { "\(image.id):\(image.revision)" }
}

public enum DistributionLocalImages {
    /// Local metadata only. Large archives stay in their original directory.
    public static func read(_ directory: URL) throws -> [DistributionLocalImage] {
        struct Index: Decodable { let schema: Int; let images: [Row] }
        struct Row: Decodable {
            let id: String; let version: String; let revision: Int; let title: String
            let coreVersion: String; let archive: String
            let expandedBytes: Int64; let archiveBytes: Int64; let archiveSHA256: String
        }
        guard directory.isFileURL else { throw DistributionError("请选择本地镜像目录") }
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let index = root.appendingPathComponent("images.json")
        guard index.resolvingSymlinksInPath().deletingLastPathComponent() == root,
              let size = try index.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576 else {
            throw DistributionError("本地 images.json 路径无效或超过 1 MiB")
        }
        let value = try JSONDecoder().decode(Index.self, from: Data(contentsOf: index))
        guard value.schema == 1, value.images.count <= 100,
              Set(value.images.map { "\($0.id):\($0.revision)" }).count == value.images.count else {
            throw DistributionError("本地镜像清单不兼容或版本重复")
        }
        return try value.images.map { row in
            guard DistributionAsset.safeName(row.id), !row.version.isEmpty, !row.title.isEmpty,
                  row.revision > 0, row.expandedBytes > 0, row.expandedBytes < Int64.max / 8,
                  row.archiveBytes > 0, row.archiveBytes < Int64.max / 8,
                  row.archiveSHA256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                  row.coreVersion.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+-local\\.[a-f0-9]{8}$", options: .regularExpression) != nil,
                  row.archive == (row.archive as NSString).lastPathComponent,
                  ["tzst", "txz"].contains((row.archive as NSString).pathExtension.lowercased()) else {
                throw DistributionError("本地镜像元数据无效：\(row.id)")
            }
            let file = root.appendingPathComponent(row.archive)
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  file.resolvingSymlinksInPath().deletingLastPathComponent() == root,
                  Int64(values.fileSize ?? -1) == row.archiveBytes else {
                throw DistributionError("本地镜像文件缺失、大小不符或不是普通归档：\(row.archive)")
            }
            let image = DistributionImage(id: row.id, version: row.version, revision: row.revision,
                title: row.title, coreVersion: row.coreVersion, expandedBytes: row.expandedBytes,
                archiveBytes: row.archiveBytes, archiveSHA256: row.archiveSHA256, parts: [])
            return DistributionLocalImage(image: image, archive: file)
        }.sorted { $0.image.id == $1.image.id ? $0.image.revision > $1.image.revision : $0.image.id < $1.image.id }
    }
}
