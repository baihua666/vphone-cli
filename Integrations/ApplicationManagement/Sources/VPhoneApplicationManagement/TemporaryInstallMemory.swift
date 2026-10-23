import Foundation

/// Business recovery only. The adapter supplies existing per-machine operations.
@MainActor public enum VPhoneTemporaryInstallMemory {
    public static func run(
        prepare: () async throws -> Void,
        install: () async throws -> Void,
        restore: @escaping @MainActor @Sendable () async throws -> Void
    ) async throws {
        var failure: Error?
        do {
            try await prepare()
            try Task.checkCancellation()
            try await install()
        } catch { failure = error }
        // Cleanup must still run when the caller was cancelled. A new unstructured
        // task inherits actor/task-local context, but not cancellation.
        do { try await Task { @MainActor in try await restore() }.value }
        catch {
            throw fail("\(failure.map { "安装未完成：\($0.localizedDescription)\n" } ?? "")恢复原内存或启动失败：\(error.localizedDescription)\n恢复记录已保留，请重试恢复。")
        }
        if let failure { throw fail("安装未完成，但原内存已恢复且虚拟机已启动。\n\(failure.localizedDescription)") }
    }
}

/// Kept in Launchpad's own support directory, never in the VM manifest.
public struct VPhoneInstallMemoryRecord: Codable, Sendable {
    public let libraryRoot: String
    public let name: String
    public let directoryIdentity: String
    public let bundle: String
    public let originalMemoryMB: Int

    public init(libraryRoot: String, name: String, directoryIdentity: String, bundle: String, originalMemoryMB: Int) {
        self.libraryRoot = libraryRoot
        self.name = name
        self.directoryIdentity = directoryIdentity
        self.bundle = bundle
        self.originalMemoryMB = originalMemoryMB
    }

    public static func read(from url: URL) throws -> Self? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let record = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard record.originalMemoryMB > 0, record.originalMemoryMB < 8192,
              record.libraryRoot.hasPrefix("/"), !record.name.isEmpty,
              !record.name.contains("/"), record.name != ".", record.name != "..",
              !record.directoryIdentity.isEmpty, !record.bundle.isEmpty else {
            throw fail("临时内存恢复记录无效，请检查记录后再操作。")
        }
        return record
    }

    public func save(to url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { throw fail("尚有未完成的内存恢复，请先恢复。") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
