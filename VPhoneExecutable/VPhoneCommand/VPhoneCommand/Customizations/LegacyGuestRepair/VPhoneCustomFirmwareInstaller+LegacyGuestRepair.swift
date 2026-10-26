import ArgumentParser
import Foundation
import FirmwarePatcher
import VPhoneCoreKit

extension VPhoneCustomFirmwareInstaller {
    /// Read the installed OID, never a freshly staged or receipt-only kernel.
    func installedKernelHypervisorRenamed(volumes: [[String: Any]], work: WorkDirectory) throws -> Bool {
        #if VPHONE_CUSTOM_LEGACY_GUEST_REPAIR
        guard let volume = volumes.first(where: { ($0["Roles"] as? [String])?.contains("Preboot") == true }),
              let device = volume["DeviceIdentifier"] as? String else {
            throw ValidationError("Cannot verify hypervisor patch pairing: no Preboot volume.")
        }
        let name = "preboot-hypervisor"
        let mount = work.file(name)
        _ = try work.directory.directory(name, create: true, mode: 0o700)
        try tool("/sbin/mount_apfs", ["-o", "rdonly,nosuid,nodev,nobrowse", "/dev/\(device)", mount.path])
        defer {
            if (try? tool("/sbin/umount", [mount.path], quiet: true)) == nil {
                _ = try? tool("/sbin/umount", ["-f", mount.path], quiet: true)
            }
        }
        let payload: Data = try {
            let root = try openGuestVolume(name, device: device, in: work)
            let candidates = try root.entries().compactMap { entry -> String? in
                let path = "\(entry)/System/Library/Caches/com.apple.kernelcaches/kernelcache"
                guard (try? root.isDirectory(entry)) == true, (try? root.isRegularFile(path)) == true else { return nil }
                return path
            }
            guard candidates.count == 1, let path = candidates.first else {
                throw ValidationError("Cannot verify hypervisor patch pairing: expected one installed kernelcache.")
            }
            let staged = work.file("hypervisor-kernel.im4p")
            try root.readData(path).write(to: staged)
            return try IM4PHandler.load(contentsOf: staged).payload
        }()
        guard let renamed = FirmwareLegacyGuestRepair.kernelHypervisorRenamed(in: payload) else {
            throw ValidationError("Cannot identify the installed hypervisor OID; refusing to guess a guest patch selection.")
        }
        print("[*] Installed kernel hypervisor OID: \(renamed ? "renamed" : "original"); guest patches must match")
        return renamed
        #else
        throw ValidationError("Legacy guest repair is disabled in this build.")
        #endif
    }

}
