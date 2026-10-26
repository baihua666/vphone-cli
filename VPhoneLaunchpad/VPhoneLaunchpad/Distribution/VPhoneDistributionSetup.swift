#if VPHONE_CUSTOM_DISTRIBUTION
import Foundation
import VPhoneDistribution

extension VPhoneDistributionModel {
    typealias SetupStep = DistributionSetupProgress.Step
    typealias SetupState = DistributionSetupProgress.State

    var setupCatalog: DistributionCatalog? { imageVersion?.catalog ?? selected }
    var imageScope: String { image?.cacheKey ?? "" }
    func launchScope(using model: VPhoneLaunchpadModel) -> String {
        imageScope + "|" + VPhoneLaunchpadMachinePath(libraryRoot: model.machines.libraryRoot, name: machineName).url.path
    }
    func stepState(_ step: SetupStep, using model: VPhoneLaunchpadModel) -> SetupState {
        switch step {
        case .permissions:
            if model.host.isChecking { return .running }
            if model.host.requiredPassed { return .completed }
            let state = setup.state(step, scope: "host")
            return state == .completed ? .pending : state
        case .core:
            guard let catalog = setupCatalog else { return .pending }
            if model.bundles.isUsable(catalog.core.version) { return .completed }
            let state = setup.state(step, scope: catalog.core.version)
            return state == .completed ? .pending : state
        case .image:
            return setup.state(step, scope: imageScope)
        case .launch:
            let state = setup.state(step, scope: launchScope(using: model))
            return state == .completed && importedMachine(using: model) == nil ? .pending : state
        }
    }
    /// Retry only the import performed in this session. A historical receipt's
    /// path alone cannot identify a VM after deletion and same-name replacement.
    func importedMachine(using model: VPhoneLaunchpadModel) -> VPhoneLaunchpadMachinePath? {
        let path = VPhoneLaunchpadMachinePath(libraryRoot: model.machines.libraryRoot, name: machineName)
        guard createdScope == launchScope(using: model), createdMachine == path,
              FileManager.default.fileExists(atPath: path.url.appendingPathComponent("config.plist").path) else { return nil }
        return path
    }
    func performStep<T>(_ step: SetupStep, scope: String,
                        operation: @MainActor () async throws -> T) async throws -> T {
        fraction = 0
        return try await setup.perform(step, scope: scope, describeError: VPhoneLaunchpadError.message(for:), operation: operation)
    }
    func recheckPermissions(using model: VPhoneLaunchpadModel) {
        run {
            try await self.performStep(.permissions, scope: "host") {
                await model.refreshHost()
                guard model.host.requiredPassed else {
                    throw DistributionError("主机检查尚未通过。请打开主机设置处理未通过的项目，然后重新检查。")
                }
                self.status = "权限与主机检查已通过，可以安装 Core。"
            }
        }
    }
    func fetchImage(_ image: DistributionImage, catalog: DistributionCatalog) async throws -> URL {
        try await performStep(.image, scope: image.cacheKey) {
            self.canPause = true
            defer { self.canPause = false }
            return try await self.downloads.image(image, tag: catalog.tag, progress: self.progress)
        }
    }
}
#endif
