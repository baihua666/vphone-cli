import Foundation
import VPhoneApplicationManagement

// Isolated lifecycle adapter doubles: no user VM, process or config is touched.
struct VPhoneLaunchpadMachinePath: Hashable, Sendable {
    let libraryRoot: String
    let name: String
    var url: URL { URL(fileURLWithPath: libraryRoot).appendingPathComponent(name) }
    var libraryArguments: [String] { ["--library-root", libraryRoot] }
}
struct VPhoneLaunchpadMachine: Codable, Sendable {
    let name: String
    let libraryRoot: String
    var memoryMB: Int
    var path: VPhoneLaunchpadMachinePath { .init(libraryRoot: libraryRoot, name: name) }
}
struct VPhoneLaunchpadMachineBinding: Codable {
    let bundle: String
    static func load(_ path: VPhoneLaunchpadMachinePath) -> Self? {
        try? JSONDecoder().decode(Self.self, from: Data(contentsOf: path.url.appendingPathComponent("binding.json")))
    }
}
struct VPhoneLaunchpadError: LocalizedError {
    let message: String
    let detail: String?
    init(_ message: String, detail: String? = nil) { self.message = message; self.detail = detail }
    var errorDescription: String? { message }
}
enum VPhoneLaunchpadCreationPipeline {
    static func ping(socketPath: String) -> Bool { true }
}
@MainActor final class VPhoneLaunchpadMachineLibrary {
    typealias Path = VPhoneLaunchpadMachinePath
    enum RunState: Equatable { case running, stopped, busy(String) }
    var installMemoryOwners: [Path: UUID] = [:]
    var actionError: VPhoneLaunchpadError?
    var panicked: Set<Path> = []
    var machine: VPhoneLaunchpadMachine
    var running = true
    var events: [String] = []
    init(_ machine: VPhoneLaunchpadMachine) { self.machine = machine }
    func state(of path: Path) -> RunState {
        if installMemoryLocked(path) { return .busy("locked") }
        return running ? .running : .stopped
    }
    func refresh() async {}
    func stop(_ path: Path) async { events.append("stop"); running = false }
    func start(_ path: Path) async { events.append("start"); running = true }
    func commandLine(for path: Path) -> Command? { Command(library: self) }
    func bundleVersion(for path: Path) -> String? { VPhoneLaunchpadMachineBinding.load(path)?.bundle }
}
@MainActor struct Command {
    let library: VPhoneLaunchpadMachineLibrary
    struct Result { let succeeded = true; let jsonData: Data?; let tail = "" }
    func run(_ arguments: [String], recordInHistory: Bool) async throws -> Result {
        precondition(arguments.prefix(2) == ["vm", "info"])
        return Result(jsonData: try JSONEncoder().encode(library.machine))
    }
    func runChecked(_ arguments: [String]) async throws {
        precondition(!library.running)
        precondition(arguments.prefix(2) == ["vm", "config"])
        precondition(arguments[3] == "--library-root")
        precondition(arguments[5] == "--memory")
        library.machine.memoryMB = Int(arguments[6])!
        library.events.append("memory:\(arguments[6])")
    }
}

@main struct InstallMemoryRecoveryTests {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let machine = VPhoneLaunchpadMachine(name: "same-name", libraryRoot: root.path, memoryMB: 3072)
        try FileManager.default.createDirectory(at: machine.path.url, withIntermediateDirectories: true)
        let binding = machine.path.url.appendingPathComponent("binding.json")
        try JSONEncoder().encode(VPhoneLaunchpadMachineBinding(bundle: "original-core")).write(to: binding)
        let library = VPhoneLaunchpadMachineLibrary(machine)
        let journal = root.appendingPathComponent("recovery.json")
        let adapter = VPhoneLaunchpadInstallMemory(library: library, recordURL: journal, progress: { _ in })

        try await adapter.retry(machine: machine) {
            precondition(library.machine.memoryMB == 8192 && library.running)
            precondition(FileManager.default.fileExists(atPath: journal.path))
            let blocked = await Task.detached { @MainActor in
                do { try library.checkInstallMemoryAccess(machine.path); return false } catch { return true }
            }.value
            precondition(blocked)
            let other = VPhoneLaunchpadMachinePath(libraryRoot: root.path + "-other", name: machine.name)
            try library.checkInstallMemoryAccess(other)
            library.events.append("install")
        }
        precondition(library.machine.memoryMB == 3072 && library.running)
        precondition(library.events == ["stop", "memory:8192", "start", "install", "stop", "memory:3072", "start"])
        precondition(library.installMemoryOwners.isEmpty)
        precondition(!FileManager.default.fileExists(atPath: journal.path))

        do {
            try await adapter.retry(machine: machine) { throw VPhoneLaunchpadError("installation failed") }
            fatalError("failed installation reported success")
        } catch {}
        precondition(library.machine.memoryMB == 3072 && library.running)
        precondition(!FileManager.default.fileExists(atPath: journal.path))

        let record = VPhoneInstallMemoryRecord(libraryRoot: root.path, name: machine.name,
            directoryIdentity: try VPhoneLaunchpadInstallMemory.identity(machine.path), bundle: "original-core", originalMemoryMB: 3072)
        try record.save(to: journal)
        library.machine.memoryMB = 8192
        library.events = []
        try await adapter.recoverPending() // Simulates reopening Launchpad: restore only.
        precondition(library.events == ["stop", "memory:3072", "start"])
        precondition(library.machine.memoryMB == 3072 && library.running)

        try record.save(to: journal)
        try JSONEncoder().encode(VPhoneLaunchpadMachineBinding(bundle: "different-core")).write(to: binding)
        library.events = []
        do { try await adapter.recoverPending(); fatalError("changed Core must refuse") } catch {}
        precondition(library.events.isEmpty)
        precondition(FileManager.default.fileExists(atPath: journal.path))
        try JSONEncoder().encode(VPhoneLaunchpadMachineBinding(bundle: "original-core")).write(to: binding)
        try FileManager.default.moveItem(at: machine.path.url, to: root.appendingPathComponent("old-directory"))
        try FileManager.default.createDirectory(at: machine.path.url, withIntermediateDirectories: true)
        try JSONEncoder().encode(VPhoneLaunchpadMachineBinding(bundle: "original-core")).write(to: binding)
        do { try await adapter.recoverPending(); fatalError("same-name replacement must refuse") } catch {}
        precondition(library.events.isEmpty)
        print("Install memory adapter: success, failure, locking, reopen, Core change and same-name replacement passed")
    }
}
