#if VPHONE_CUSTOM_LEGACY_GUEST_REPAIR
import Foundation

/// Local legacy-guest recovery policy; the upstream resolver stays unchanged.
public enum FirmwareLegacyGuestRepair {
    /// GuestMobileGestaltCache observes this System-volume marker at startup.
    public static let mobileGestaltInvalidationMarker = "System/Library/Caches/com.vphone.MobileGestalt.invalidate"

    /// Legacy imports have no selection. This is also used by the dyld pass,
    /// so its decision cannot diverge from the rest of the guest update.
    public static func legacyEnabled(_ identifier: String, priorGuest: Set<String>, kernelHypervisorRenamed: Bool?) -> Bool {
        if FirmwarePatchSetCatalog.hypervisorConcealmentPatches.contains(identifier) {
            return kernelHypervisorRenamed == true
        }
        // An existing opt-in is not permission to enable every other experiment.
        if identifier.contains("-exp-") { return priorGuest.contains(identifier) }
        return !FirmwareGuestSystemPatchSet.settingsRowPatches.contains(identifier)
            && identifier != FirmwareGuestSystemPatchSet.gyroscope
            && identifier != FirmwareGuestSystemPatchSet.accelerometer
            && identifier != FirmwareGuestSystemPatchSet.attitude
    }

    /// Match the NUL-delimited OID name, not callers mentioning another name.
    /// Both names or neither name are ambiguous; never guess from a receipt.
    public static func kernelHypervisorRenamed(in payload: Data) -> Bool? {
        let original = payload.range(of: Data("\0hv_vmm_present\0".utf8)) != nil
        let renamed = payload.range(of: Data("\0Xv_vmm_present\0".utf8)) != nil
        guard original != renamed else { return nil }
        return renamed
    }

    public static func hypervisorGuestMatchesKernel(enabled: Set<String>, kernelRenamed: Bool) -> Bool {
        FirmwarePatchSetCatalog.hypervisorConcealmentPatches
            .subtracting(["kernel-exp-hv_vmm"])
            .allSatisfy { enabled.contains($0) == kernelRenamed }
    }

}
#endif
