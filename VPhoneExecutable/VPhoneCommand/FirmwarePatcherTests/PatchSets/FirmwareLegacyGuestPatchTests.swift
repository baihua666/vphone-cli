#if VPHONE_CUSTOM_LEGACY_GUEST_REPAIR
import FirmwarePatcher
import Foundation
import Testing

@Suite("Legacy guest patch safety")
struct FirmwareLegacyGuestPatchTests {
    @Test func `missing plan never guesses that an experimental patch was selected`() {
        for patch in FirmwarePatchSetCatalog.allDeclarations where patch.identifier.contains("-exp-") {
            #expect(!FirmwareLegacyGuestRepair.legacyEnabled(patch.identifier, priorGuest: [], kernelHypervisorRenamed: false))
        }
        #expect(FirmwareLegacyGuestRepair.legacyEnabled("system-vphoned-boot-install", priorGuest: [], kernelHypervisorRenamed: false))
    }

    @Test func `recorded userland concealment is removed with an unrenamed kernel`() {
        let applied: Set<String> = ["dyld-exp-hv_vmm", "system-watchdogd-exp-hv_vmm_cache", "dyld-exp-mis_trust_auth"]
        #expect(!FirmwareLegacyGuestRepair.legacyEnabled("dyld-exp-hv_vmm", priorGuest: applied, kernelHypervisorRenamed: false))
        #expect(!FirmwareLegacyGuestRepair.legacyEnabled("system-watchdogd-exp-hv_vmm_cache", priorGuest: applied, kernelHypervisorRenamed: false))
        #expect(FirmwareLegacyGuestRepair.legacyEnabled("dyld-exp-mis_trust_auth", priorGuest: applied, kernelHypervisorRenamed: false))
    }

    @Test func `a renamed legacy kernel retains its required guest halves`() {
        for identifier in ["dyld-exp-hv_vmm", "system-watchdogd-exp-hv_vmm_cache"] {
            #expect(FirmwareLegacyGuestRepair.legacyEnabled(identifier, priorGuest: [], kernelHypervisorRenamed: true))
        }
    }

    @Test func `kernel state comes from the OID rather than cached caller strings`() {
        let original = Data("\0hv_vmm_present\0\0kern.Xv_vmm_present\0".utf8)
        let renamed = Data("\0Xv_vmm_present\0\0kern.hv_vmm_present\0".utf8)
        #expect(FirmwareLegacyGuestRepair.kernelHypervisorRenamed(in: original) == false)
        #expect(FirmwareLegacyGuestRepair.kernelHypervisorRenamed(in: renamed) == true)
        #expect(FirmwareLegacyGuestRepair.kernelHypervisorRenamed(in: Data()) == nil)
        #expect(FirmwareLegacyGuestRepair.kernelHypervisorRenamed(in: original + renamed) == nil)
    }

    @Test func `explicit guest selection must match both installed kernel and watchdog`() {
        let pair: Set<String> = ["dyld-exp-hv_vmm", "system-watchdogd-exp-hv_vmm_cache"]
        #expect(FirmwareLegacyGuestRepair.hypervisorGuestMatchesKernel(enabled: [], kernelRenamed: false))
        #expect(FirmwareLegacyGuestRepair.hypervisorGuestMatchesKernel(enabled: pair, kernelRenamed: true))
        #expect(!FirmwareLegacyGuestRepair.hypervisorGuestMatchesKernel(enabled: pair, kernelRenamed: false))
        #expect(!FirmwareLegacyGuestRepair.hypervisorGuestMatchesKernel(enabled: [], kernelRenamed: true))
        #expect(!FirmwareLegacyGuestRepair.hypervisorGuestMatchesKernel(enabled: ["dyld-exp-hv_vmm"], kernelRenamed: true))
    }
}

#endif
