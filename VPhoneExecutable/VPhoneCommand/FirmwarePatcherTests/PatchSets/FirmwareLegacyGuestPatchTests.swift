import FirmwarePatcher
import Foundation
import Testing

@Suite("Legacy guest patch safety")
struct FirmwareLegacyGuestPatchTests {
    @Test func `missing plan never guesses that an experimental patch was selected`() {
        for patch in FirmwarePatchSetCatalog.allDeclarations where patch.identifier.contains("-exp-") {
            #expect(!FirmwareGuestPatchResolution.legacyEnabled(patch.identifier, priorGuest: [], kernelHypervisorRenamed: false))
        }
        #expect(FirmwareGuestPatchResolution.legacyEnabled("system-vphoned-boot-install", priorGuest: [], kernelHypervisorRenamed: false))
    }

    @Test func `recorded userland concealment is removed with an unrenamed kernel`() {
        let applied: Set<String> = ["dyld-exp-hv_vmm", "system-watchdogd-exp-hv_vmm_cache", "dyld-exp-mis_trust_auth"]
        #expect(!FirmwareGuestPatchResolution.legacyEnabled("dyld-exp-hv_vmm", priorGuest: applied, kernelHypervisorRenamed: false))
        #expect(!FirmwareGuestPatchResolution.legacyEnabled("system-watchdogd-exp-hv_vmm_cache", priorGuest: applied, kernelHypervisorRenamed: false))
        #expect(FirmwareGuestPatchResolution.legacyEnabled("dyld-exp-mis_trust_auth", priorGuest: applied, kernelHypervisorRenamed: false))
    }

    @Test func `a renamed legacy kernel retains its required guest halves`() {
        for identifier in ["dyld-exp-hv_vmm", "system-watchdogd-exp-hv_vmm_cache"] {
            #expect(FirmwareGuestPatchResolution.legacyEnabled(identifier, priorGuest: [], kernelHypervisorRenamed: true))
        }
    }

    @Test func `kernel state comes from the OID rather than cached caller strings`() {
        let original = Data("\0hv_vmm_present\0\0kern.Xv_vmm_present\0".utf8)
        let renamed = Data("\0Xv_vmm_present\0\0kern.hv_vmm_present\0".utf8)
        #expect(FirmwareGuestPatchResolution.kernelHypervisorRenamed(in: original) == false)
        #expect(FirmwareGuestPatchResolution.kernelHypervisorRenamed(in: renamed) == true)
        #expect(FirmwareGuestPatchResolution.kernelHypervisorRenamed(in: Data()) == nil)
        #expect(FirmwareGuestPatchResolution.kernelHypervisorRenamed(in: original + renamed) == nil)
    }

    @Test func `explicit guest selection must match both installed kernel and watchdog`() {
        let pair: Set<String> = ["dyld-exp-hv_vmm", "system-watchdogd-exp-hv_vmm_cache"]
        #expect(FirmwareGuestPatchResolution.hypervisorGuestMatchesKernel(enabled: [], kernelRenamed: false))
        #expect(FirmwareGuestPatchResolution.hypervisorGuestMatchesKernel(enabled: pair, kernelRenamed: true))
        #expect(!FirmwareGuestPatchResolution.hypervisorGuestMatchesKernel(enabled: pair, kernelRenamed: false))
        #expect(!FirmwareGuestPatchResolution.hypervisorGuestMatchesKernel(enabled: [], kernelRenamed: true))
        #expect(!FirmwareGuestPatchResolution.hypervisorGuestMatchesKernel(enabled: ["dyld-exp-hv_vmm"], kernelRenamed: true))
    }
}
