import Foundation

@main struct GuestMobileGestaltCacheTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("cache.plist")
        let tree = root.appendingPathComponent("tree")
        let marker = root.appendingPathComponent("repair-marker")
        func write(_ file: URL, at time: Double) throws {
            try Data("fixture".utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: time)], ofItemAtPath: file.path)
        }
        try write(tree, at: 100)
        try write(cache, at: 200)
        precondition(!GuestMobileGestaltCache.dropIfOlder(cache: cache.path, sources: [tree.path, marker.path]))
        try write(marker, at: 300)
        precondition(GuestMobileGestaltCache.dropIfOlder(cache: cache.path, sources: [tree.path, marker.path]))
        precondition(!FileManager.default.fileExists(atPath: cache.path))
        precondition(!GuestMobileGestaltCache.dropIfOlder(cache: cache.path, sources: [marker.path]))
        try write(cache, at: 300)
        precondition(!GuestMobileGestaltCache.dropIfOlder(cache: cache.path, sources: [marker.path]))
        try write(cache, at: 400)
        precondition(!GuestMobileGestaltCache.dropIfOlder(cache: cache.path, sources: [marker.path]))
        try write(tree, at: 500)
        precondition(GuestMobileGestaltCache.dropIfOlder(cache: cache.path, sources: [tree.path, marker.path]))
        let hostSource = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        precondition(hostSource.contains("\"" + String(GuestMobileGestaltCache.hypervisorMarker.dropFirst()) + "\""), "host/guest marker paths disagree")
        print("PASS: repair marker invalidates old hardware answers, keeps rebuilt caches, preserves tree invalidation and host/guest path contract")
    }
}
