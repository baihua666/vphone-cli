#if VPHONE_CUSTOM_APPLICATION_MANAGEMENT && VPHONE_CUSTOM_TEMPORARY_INSTALL_MEMORY
import Foundation
import VPhoneApplicationManagement

extension VPhoneLaunchpadApplicationsModel {
    var memoryRecordURL: URL { cache.deletingLastPathComponent().appendingPathComponent("install-memory-recovery.json") }

    func memoryAdapter(_ library: VPhoneLaunchpadMachineLibrary) -> VPhoneLaunchpadInstallMemory {
        VPhoneLaunchpadInstallMemory(library: library, recordURL: memoryRecordURL, progress: { self.status = $0 })
    }

    func retryWithMemory(using library: VPhoneLaunchpadMachineLibrary) {
        guard let candidate = memoryRetry, !busy else { return }
        memoryRetry = nil
        showMemoryRetry = false
        perform {
            defer { self.memoryRecoveryPending = FileManager.default.fileExists(atPath: self.memoryRecordURL.path) }
            // Explicitly fixed target: changing the picker cannot redirect a retry.
            self.machinePath = candidate.machine.path.url.path
            try await Task.detached { try VPhoneApplicationLibrary.validate(candidate.app.url) }.value
            try await self.memoryAdapter(library).retry(machine: candidate.machine) {
                try await self.installOnce(candidate.app, machine: candidate.machine)
            }
            self.status = "\(candidate.app.name) 安装成功；\(candidate.machine.name) 已恢复原内存并启动。"
        }
    }

    func recoverInstallMemory(using library: VPhoneLaunchpadMachineLibrary) {
        memoryRecoveryPending = FileManager.default.fileExists(atPath: memoryRecordURL.path)
        guard memoryRecoveryPending, !busy else { return }
        perform {
            defer { self.memoryRecoveryPending = FileManager.default.fileExists(atPath: self.memoryRecordURL.path) }
            do { try await self.memoryAdapter(library).recoverPending() }
            catch {
                library.actionError = VPhoneLaunchpadError("原内存尚未恢复或虚拟机尚未就绪，请打开应用管理重试恢复。", detail: VPhoneLaunchpadError.message(for: error))
                throw error
            }
            self.status = "未完成的临时增配流程已恢复：原内存已还原，虚拟机已启动；未自动重试安装。"
        }
    }
}
#endif
