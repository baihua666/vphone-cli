import Foundation
#if VPHONE_CUSTOM_LEGACY_GUEST_REPAIR
import ArgumentParser
import FirmwarePatcher
#endif

/// Static hooks for one local repair. Disabled builds return no overrides and
/// never execute the supplied kernel reader or marker writer.
enum VPhoneLegacyGuestRepairHooks {
    static func prepare(plan: Set<String>?, priorGuest: Set<String>, readKernel: () throws -> Bool) throws -> Bool? {
        #if VPHONE_CUSTOM_LEGACY_GUEST_REPAIR
        guard plan == nil || !(plan ?? []).union(priorGuest)
            .isDisjoint(with: FirmwarePatchSetCatalog.hypervisorConcealmentPatches) else { return nil }
        let renamed = try readKernel()
        if let plan, !FirmwareLegacyGuestRepair.hypervisorGuestMatchesKernel(enabled: plan, kernelRenamed: renamed) {
            throw ValidationError("Guest hypervisor patches do not match the installed kernel. Update the kernel and its paired selection together; guest files were not committed.")
        }
        return renamed
        #else
        return nil
        #endif
    }

    static func legacyEnabled(_ identifier: String, priorGuest: Set<String>, kernelHypervisorRenamed: Bool?) -> Bool? {
        #if VPHONE_CUSTOM_LEGACY_GUEST_REPAIR
        FirmwareLegacyGuestRepair.legacyEnabled(identifier, priorGuest: priorGuest,
            kernelHypervisorRenamed: kernelHypervisorRenamed)
        #else
        nil
        #endif
    }

    static func wasApplied(prior: Bool, undo: Bool) -> Bool {
        #if VPHONE_CUSTOM_LEGACY_GUEST_REPAIR
        prior || undo
        #else
        prior
        #endif
    }

    static func didFinishDyld(prior: Set<String>, recorded: Set<String>, live: Set<String>,
                              write: (String, Data) throws -> Void) throws {
        #if VPHONE_CUSTOM_LEGACY_GUEST_REPAIR
        let identifier = "dyld-exp-hv_vmm"
        guard (prior.contains(identifier) || recorded.contains(identifier)) != live.contains(identifier) else { return }
        try write(FirmwareLegacyGuestRepair.mobileGestaltInvalidationMarker, Data(UUID().uuidString.utf8))
        print("  [+] MobileGestalt cache invalidation scheduled for the hypervisor state change; restart after the first boot")
        #endif
    }

    static var missingPlanMessage: String {
        #if VPHONE_CUSTOM_LEGACY_GUEST_REPAIR
        "[*] No patch plan recorded; preserving recorded opt-ins and verifying hypervisor pairing"
        #else
        "[*] No patch plan recorded; applying every guest patch"
        #endif
    }

    static var unreadablePlanMessage: String {
        #if VPHONE_CUSTOM_LEGACY_GUEST_REPAIR
        "[!] PatchPlan.plist is unreadable; using the verified legacy guest policy"
        #else
        "[!] PatchPlan.plist is unreadable; applying every guest patch"
        #endif
    }
}
