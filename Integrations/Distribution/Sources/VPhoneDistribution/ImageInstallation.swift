import Foundation

public enum ImageInstallation {
    public typealias Command = @Sendable ([String]) async throws -> Void
    /// Use existing import + clone --new-identity. Work happens in a private
    /// staging library on the destination volume, never on an existing VM.
    /// A move publishes the finished directory without overwriting a target.
    public static func prepare(archive: URL, library: URL, name: String,
                               finalize: @Sendable (URL) async throws -> Void = { _ in },
                               run: Command) async throws -> URL {
        guard DistributionAsset.safeName(name) else { throw DistributionError("实例名只允许英文字母、数字、点、横线和下划线") }
        let fm = FileManager.default
        try fm.createDirectory(at: library, withIntermediateDirectories: true)
        let destination = library.appendingPathComponent(name, isDirectory: true)
        guard !fm.fileExists(atPath: destination.path) else { throw DistributionError("同名实例已存在，不会覆盖") }
        let stage = library.appendingPathComponent(".distribution-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        // Staging machines are never started. Safe to remove only this owned directory.
        defer { try? fm.removeItem(at: stage) }
        try Task.checkCancellation()
        let templateName = "template-" + UUID().uuidString
        try await run(["vm", "import", archive.path, "--name", templateName, "--library-root", stage.path])
        try Task.checkCancellation()
        try await run(["vm", "clone", templateName, name, "--new-identity", "--library-root", stage.path])
        try Task.checkCancellation()
        let ready = stage.appendingPathComponent(name, isDirectory: true)
        guard fm.fileExists(atPath: ready.appendingPathComponent("config.plist").path) else {
            throw DistributionError("导入未生成有效实例目录")
        }
        try await finalize(ready)
        try Task.checkCancellation()
        try fm.moveItem(at: ready, to: destination)
        return destination
    }
}

/// Separate from VM manifests. A template update never overwrites guest disks.
public struct DistributionReceipt: Codable, Sendable, Identifiable {
    public let id: UUID
    public let imageID: String
    public let imageVersion: String
    public let revision: Int
    public let sha256: String
    public let machinePath: String
    public let installedAt: Date
    public init(image: DistributionImage, machinePath: String) {
        id = UUID(); imageID = image.id; imageVersion = image.version; revision = image.revision
        sha256 = image.archiveSHA256; self.machinePath = machinePath; installedAt = Date()
    }
    public func updateAvailable(_ image: DistributionImage) -> Bool {
        image.id == imageID && image.revision > revision
    }
}
