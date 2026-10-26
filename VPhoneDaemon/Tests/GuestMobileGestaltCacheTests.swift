import Foundation

@main struct GuestMobileGestaltCacheTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("cache.plist")
        let marker = root.appendingPathComponent("repair-marker")
        func write(_ file: URL, at time: Double) throws {
            try Data("fixture".utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: time)], ofItemAtPath: file.path)
        }
        try write(cache, at: 200)
        precondition(!GuestLegacyGuestRepairHooks.needsInvalidation(cache: cache.path, marker: marker.path))
        try write(marker, at: 300)
        #if VPHONE_CUSTOM_LEGACY_GUEST_REPAIR
        precondition(GuestLegacyGuestRepairHooks.needsInvalidation(cache: cache.path, marker: marker.path))
        #else
        precondition(!GuestLegacyGuestRepairHooks.needsInvalidation(cache: cache.path, marker: marker.path))
        #endif
        precondition(FileManager.default.fileExists(atPath: cache.path), "hook must not own deletion")
        precondition(!GuestLegacyGuestRepairHooks.needsInvalidation(cache: root.appendingPathComponent("missing").path, marker: marker.path))
        try write(cache, at: 300)
        precondition(!GuestLegacyGuestRepairHooks.needsInvalidation(cache: cache.path, marker: marker.path))
        try write(cache, at: 400)
        precondition(!GuestLegacyGuestRepairHooks.needsInvalidation(cache: cache.path, marker: marker.path))
        #if VPHONE_CUSTOM_LEGACY_GUEST_REPAIR
        let hostSource = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        precondition(hostSource.contains("\"" + String(GuestLegacyGuestRepairHooks.marker.dropFirst()) + "\""), "host/guest marker paths disagree")
        #endif
        print("PASS: isolated guest hook, enabled/disabled invalidation, rebuilt cache preservation and host/guest path contract")
    }
}
