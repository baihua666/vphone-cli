#if VPHONE_CUSTOM_APPLICATION_MANAGEMENT && VPHONE_CUSTOM_TEMPORARY_INSTALL_MEMORY
import Foundation
import VPhoneApplicationManagement

enum VPhoneInstallMemoryOwner {
    @TaskLocal static var id: UUID?
}

extension VPhoneLaunchpadMachineLibrary {
    func checkInstallMemoryAccess(_ machine: Path) throws {
        if let owner = installMemoryOwners[machine], owner != VPhoneInstallMemoryOwner.id {
            throw VPhoneLaunchpadError("\(machine.name) 正在临时增配安装或等待恢复原内存，请在应用管理中完成恢复。")
        }
    }

    func installMemoryLocked(_ machine: Path) -> Bool {
        installMemoryOwners[machine] != nil && installMemoryOwners[machine] != VPhoneInstallMemoryOwner.id
    }
}

/// Uses the selected machine's existing CLI and Launchpad's normal lifecycle.
@MainActor struct VPhoneLaunchpadInstallMemory {
    let library: VPhoneLaunchpadMachineLibrary
    let recordURL: URL
    let progress: (String) -> Void

    static func identity(_ path: VPhoneLaunchpadMachinePath) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: path.url.path)
        guard let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else {
            throw VPhoneLaunchpadError("无法确认虚拟机目录身份")
        }
        return "\(device):\(inode)"
    }

    func inspect(_ path: VPhoneLaunchpadMachinePath) async throws -> VPhoneLaunchpadMachine {
        guard let cli = library.commandLine(for: path) else { throw VPhoneLaunchpadError("目标实例的 Core 不可用") }
        let result = try await cli.run(["vm", "info", path.name, "--json"] + path.libraryArguments, recordInHistory: false)
        guard result.succeeded, let data = result.jsonData else { throw VPhoneLaunchpadError("无法核对目标实例配置", detail: result.tail) }
        return try JSONDecoder().decode(VPhoneLaunchpadMachine.self, from: data)
    }

    func validate(_ record: VPhoneInstallMemoryRecord) throws -> VPhoneLaunchpadMachinePath {
        let path = VPhoneLaunchpadMachinePath(libraryRoot: record.libraryRoot, name: record.name)
        guard try Self.identity(path) == record.directoryIdentity,
              VPhoneLaunchpadMachineBinding.load(path)?.bundle == record.bundle else {
            throw VPhoneLaunchpadError("实例目录或 Core 绑定已改变，未修改此实例；请核对后恢复原内存。")
        }
        return path
    }

    func stop(_ path: VPhoneLaunchpadMachinePath) async throws {
        library.actionError = nil
        await library.stop(path)
        if let error = library.actionError { library.actionError = nil; throw error }
        // The CLI's stop may return before the child exits. Never configure live RAM.
        for _ in 0..<30 {
            await library.refresh()
            if library.state(of: path) == .stopped { return }
            try await Task.sleep(for: .seconds(1))
        }
        throw VPhoneLaunchpadError("虚拟机未停止，未更改内存")
    }

    func setMemory(_ memory: Int, record: VPhoneInstallMemoryRecord) async throws {
        let path = try validate(record)
        guard library.state(of: path) == .stopped, let cli = library.commandLine(for: path) else {
            throw VPhoneLaunchpadError("必须确认虚拟机停止后才能调整内存")
        }
        try await cli.runChecked(["vm", "config", path.name] + path.libraryArguments + ["--memory", String(memory)])
        guard try await inspect(path).memoryMB == memory else { throw VPhoneLaunchpadError("内存配置读回不一致") }
        await library.refresh()
    }

    func start(_ path: VPhoneLaunchpadMachinePath) async throws {
        if library.state(of: path) == .stopped {
            library.actionError = nil
            await library.start(path)
            if let error = library.actionError { library.actionError = nil; throw error }
        }
        let socket = path.url.appendingPathComponent("vphone.sock").path
        for _ in 0..<120 {
            try Task.checkCancellation()
            if library.panicked.contains(path) { throw VPhoneLaunchpadError("虚拟机启动时发生内核异常") }
            if await Task.detached(operation: { VPhoneLaunchpadCreationPipeline.ping(socketPath: socket) }).value { return }
            try await Task.sleep(for: .seconds(1))
        }
        throw VPhoneLaunchpadError("虚拟机已请求启动，但 120 秒内客体未就绪")
    }

    func restore(_ record: VPhoneInstallMemoryRecord) async throws {
        let path = try validate(record)
        progress("正在恢复 \(path.name) 原内存 \(record.originalMemoryMB) MB 并启动…")
        if try await inspect(path).memoryMB != record.originalMemoryMB {
            try await stop(path)
            try await setMemory(record.originalMemoryMB, record: record)
        }
        try await start(path)
        guard try await inspect(path).memoryMB == record.originalMemoryMB else { throw VPhoneLaunchpadError("原内存恢复校验失败") }
        try FileManager.default.removeItem(at: recordURL)
        library.installMemoryOwners[path] = nil
    }

    func retry(machine: VPhoneLaunchpadMachine, install: () async throws -> Void) async throws {
        let path = machine.path
        try library.checkInstallMemoryAccess(path)
        if case .busy = library.state(of: path) { throw VPhoneLaunchpadError("实例正在执行其它操作") }
        let owner = UUID()
        library.installMemoryOwners[path] = owner
        try await VPhoneInstallMemoryOwner.$id.withValue(owner) {
            var saved = false
            do {
                let current = try await inspect(path)
                guard current.memoryMB > 0, current.memoryMB < 8192,
                      let bundle = library.bundleVersion(for: path) else {
                    throw VPhoneLaunchpadError("仅为原内存小于 8 GB 的实例提供临时增配重试")
                }
                let record = VPhoneInstallMemoryRecord(libraryRoot: path.libraryRoot, name: path.name,
                    directoryIdentity: try Self.identity(path), bundle: bundle, originalMemoryMB: current.memoryMB)
                try record.save(to: recordURL) // Durable before the first lifecycle mutation.
                saved = true
                try await VPhoneTemporaryInstallMemory.run(prepare: {
                    progress("正在停止 \(path.name)，临时调整为 8 GB…")
                    try await stop(path)
                    try await setMemory(8192, record: record)
                    progress("正在以 8 GB 启动 \(path.name)…")
                    try await start(path)
                }, install: install, restore: { try await restore(record) })
            } catch {
                if !saved || !FileManager.default.fileExists(atPath: recordURL.path) { library.installMemoryOwners[path] = nil }
                throw error
            }
        }
    }

    func recoverPending() async throws {
        guard let record = try VPhoneInstallMemoryRecord.read(from: recordURL) else { return }
        let path = try validate(record)
        let owner = UUID()
        library.installMemoryOwners[path] = owner
        try await VPhoneInstallMemoryOwner.$id.withValue(owner) { try await restore(record) }
    }
}
#endif
