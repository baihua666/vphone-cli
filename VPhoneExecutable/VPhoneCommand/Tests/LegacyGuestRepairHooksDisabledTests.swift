import Foundation

@main struct LegacyGuestRepairHooksDisabledTests {
    static func main() throws {
        #if VPHONE_CUSTOM_LEGACY_GUEST_REPAIR
        fatalError("This test must compile the disabled adapter")
        #else
        var reads = 0
        var writes = 0
        let result = try VPhoneLegacyGuestRepairHooks.prepare(plan: nil, priorGuest: ["dyld-exp-hv_vmm"]) {
            reads += 1
            return false
        }
        precondition(result == nil && reads == 0)
        precondition(VPhoneLegacyGuestRepairHooks.legacyEnabled("dyld-exp-hv_vmm", priorGuest: [], kernelHypervisorRenamed: false) == nil)
        precondition(!VPhoneLegacyGuestRepairHooks.wasApplied(prior: false, undo: true))
        try VPhoneLegacyGuestRepairHooks.didFinishDyld(prior: ["dyld-exp-hv_vmm"], recorded: [], live: []) { _, _ in
            writes += 1
        }
        precondition(writes == 0)
        precondition(VPhoneLegacyGuestRepairHooks.missingPlanMessage.contains("applying every guest patch"))
        print("PASS: disabled host hooks do not inspect kernels, override legacy decisions or write guest markers")
        #endif
    }
}
