#if VPHONE_CUSTOM_DISTRIBUTION && VPHONE_CUSTOM_APP_UPDATE
import AppKit
import VPhoneDistribution

extension VPhoneDistributionModel {
    var hasAppUpdate: Bool { catalogs.first.map { $0.app.revision > currentRevision } ?? false }

    func updateApp(using platform: VPhoneLaunchpadModel) {
        guard let catalog = catalogs.first, hasAppUpdate else { return }
        run {
            self.updatingApp = true
            defer { self.updatingApp = false }
            try await self.requireUpdateIdle(platform)
            guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= catalog.app.minimumMacOS else {
                throw DistributionError("此更新需要 macOS \(catalog.app.minimumMacOS) 或更新版本")
            }
            self.status = "正在下载 Launchpad 更新…"
            self.canPause = true
            let dmg = try await self.downloads.asset(catalog.app.asset, tag: catalog.tag, progress: self.progress)
            try Task.checkCancellation()
            self.canPause = false
            self.status = "正在校验并准备安装更新…"
            let prepared = try await VPhoneLaunchpadAppUpdate.prepare(dmg: dmg, destination: Bundle.main.bundleURL,
                revision: catalog.app.revision, baseline: catalog.app.baseline)
            do {
                try await self.requireUpdateIdle(platform)
                try FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
                let installerPID = try await VPhoneLaunchpadAppUpdate.handoff(prepared, parent: ProcessInfo.processInfo.processIdentifier,
                    report: Self.root.appendingPathComponent("app-update-error.txt"))
                do { try await self.requireUpdateIdle(platform) }
                catch { kill(installerPID, SIGTERM); throw error }
            } catch {
                try? FileManager.default.removeItem(at: prepared.directory)
                throw error
            }
            self.status = "即将安装更新并重启 Launchpad…"
            self.busy = false
            NSApp.terminate(nil)
        }
    }

    private func requireUpdateIdle(_ platform: VPhoneLaunchpadModel) async throws {
        await platform.machines.refresh()
        guard !platform.machines.hasActiveCreation, !platform.machines.hasActiveTransfer,
              platform.machines.machines.allSatisfy({ platform.machines.state(of: $0.path) == .stopped }) else {
            throw DistributionError("请先正常停止虚拟机，并等待创建、导入或导出完成，再点击更新。当前 App 未替换。")
        }
    }
}
#endif
