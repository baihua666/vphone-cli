import Darwin
import Foundation

enum GuestLegacyGuestRepairHooks {
    #if VPHONE_CUSTOM_LEGACY_GUEST_REPAIR
    // Cross-process contract with FirmwareLegacyGuestRepair.
    static let marker = "/System/Library/Caches/com.vphone.MobileGestalt.invalidate"
    #endif

    /// A read-only extension to the upstream invalidation condition. The
    /// upstream cache owner still owns deletion and restart reporting.
    static func needsInvalidation(cache: String, marker suppliedMarker: String? = nil) -> Bool {
        #if VPHONE_CUSTOM_LEGACY_GUEST_REPAIR
        var cached = stat()
        var repaired = stat()
        guard lstat(cache, &cached) == 0, cached.st_mode & S_IFMT == S_IFREG,
              lstat(suppliedMarker ?? marker, &repaired) == 0, repaired.st_mode & S_IFMT == S_IFREG else { return false }
        let a = cached.st_mtimespec
        let b = repaired.st_mtimespec
        return a.tv_sec != b.tv_sec ? a.tv_sec < b.tv_sec : a.tv_nsec < b.tv_nsec
        #else
        return false
        #endif
    }
}
