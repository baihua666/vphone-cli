import Foundation
import Darwin

// Compile the real pipeline; substitute only its process/helper dependencies.
enum VPhoneLaunchpadStatus { case pending, running, passed, failed }
struct VPhoneLaunchpadError: Error { let message: String; var detail: String?; init(_ message: String, detail: String? = nil) { self.message = message; self.detail = detail } }
struct VPhoneLaunchpadPatchSelection: Sendable {
    var presetArguments: [String] { [] }; var hasOverrides: Bool { false }; var setPatchesArguments: [String] { [] }
}
struct VPhoneLaunchpadMachinePath: Hashable, Sendable {
    let libraryRoot: String; let name: String
    var url: URL { URL(fileURLWithPath: libraryRoot).appendingPathComponent(name) }
    var libraryArguments: [String] { ["--library-root", libraryRoot] }
}
final class VPhoneLaunchpadLogWriter: @unchecked Sendable {
    let url: URL; init(url: URL) { self.url = url }
    var tail: String { "test log" }; func write(_ line: String) {}
}
struct VPhoneLaunchpadMachineBinding { let bundle: String; let bootChain: String }
enum VPhoneLaunchpadPanicLine { static func matches(_ line: String) -> Bool { false } }
@MainActor final class VPhoneLaunchpadChildProcess { var isRunning = true; func terminate() {} }
@MainActor final class VPhoneLaunchpadCommandLine {
    var calls: [[String]] = []
    static func display(_ arguments: [String]) -> String { arguments.joined(separator: " ") }
    func runChecked(_ arguments: [String], onLine: @escaping @Sendable (String) -> Void,
                    onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        calls.append(arguments)
    }
    struct Result { let succeeded = true }
    func run(_ arguments: [String], recordInHistory: Bool) async throws -> Result { Result() }
    func start(_ arguments: [String], logFile: URL, onLine: @escaping @Sendable (String) -> Void) throws -> VPhoneLaunchpadChildProcess { VPhoneLaunchpadChildProcess() }
}
@MainActor final class VPhoneLaunchpadCoreBundle {
    let cli = VPhoneLaunchpadCommandLine()
    var versions: [String] = []
    func isChecked(_ version: String) -> Bool { true }
    func prepare(_ version: String) async throws {}
    func commandLine(version: String) -> VPhoneLaunchpadCommandLine? { versions.append(version); return cli }
}
@MainActor final class VPhoneLaunchpadHelperClient {
    func installCustomFirmware(bundleVersion: String, machineName: String, libraryRoot: String,
                               keepArtifacts: Bool, onLine: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        fatalError("Initialization must never install firmware")
    }
}
@MainActor final class VPhoneLaunchpadMachineLibrary {
    var panicked: Set<VPhoneLaunchpadMachinePath> = []
    var starts = 0
    func bind(_ machine: VPhoneLaunchpadMachinePath, _ binding: VPhoneLaunchpadMachineBinding) throws {}
    func refresh() async {}
    func recordGuestEnvironment(_ machine: VPhoneLaunchpadMachinePath, _ version: String) {}
    func start(_ machine: VPhoneLaunchpadMachinePath) async {
        starts += 1
        try! FileManager.default.createDirectory(at: machine.url, withIntermediateDirectories: true)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = machine.url.appendingPathComponent("vphone.sock").path.utf8CString
        precondition(path.count <= MemoryLayout.size(ofValue: address.sun_path))
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in path.enumerated() { buffer[index] = UInt8(bitPattern: byte) }
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        precondition(fd >= 0)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        precondition(bound == 0 && listen(fd, 1) == 0)
        Task.detached {
            defer { close(fd) }
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            defer { close(client) }
            var bytes = [UInt8](repeating: 0, count: 512)
            _ = read(client, &bytes, bytes.count)
            let reply = Data("{\"ok\":true}\n".utf8)
            _ = reply.withUnsafeBytes { Darwin.write(client, $0.baseAddress, $0.count) }
        }
    }
    func launchedProcess(_ machine: VPhoneLaunchpadMachinePath) -> VPhoneLaunchpadChildProcess? { VPhoneLaunchpadChildProcess() }
    static func consoleLog(_ machine: VPhoneLaunchpadMachinePath, suffix: String) -> URL { machine.url.appendingPathComponent(suffix) }
}

// Policy itself is tested separately with its clock. Here it is a boundary
// dependency, so the real adapter and pipeline can be exercised without 120 s.
@MainActor enum VPhoneDeviceInitialization {
    static var shouldFail = true
    static func run(rpc: (String, [String: Any], Int) async throws -> [String: Any],
                    onProgress: (String) -> Void) async throws {
        _ = try await rpc("display.auto_lock", [:], 10)
        if shouldFail { throw VPhoneLaunchpadError("verification failed") }
    }
}
@MainActor enum VPhoneLaunchpadGuestSocket {
    static var paths: [String] = []
    static var malformed = false
    static func send(_ object: [String: Any], socketPath: String, timeout: Int) async throws -> Any {
        paths.append(socketPath)
        precondition(object["method"] as? String == "display.auto_lock")
        let reply: [String: Any] = malformed ? ["ok": true] : ["ok": true, "result": ["set_supported": true]]
        return reply
    }
}

@main struct CreationInitializationTests {
    @MainActor static func main() async throws {
        let bundles = VPhoneLaunchpadCoreBundle()
        let library = VPhoneLaunchpadMachineLibrary()
        let root = "/tmp/vp-init-\(UUID().uuidString.prefix(8))"
        defer { try? FileManager.default.removeItem(atPath: root) }
        let options = VPhoneLaunchpadCreationPipeline.Options(
            name: "new-phone", libraryRoot: root, bundleVersion: "2.9.0-local.abcdef12",
            iphoneSource: "iphone", cloudOSSource: "cloud", cpuCount: 4, memoryMB: 4096,
            diskSizeGB: 64, network: "nat", patches: VPhoneLaunchpadPatchSelection(), keepArtifacts: true,
        )
        let pipeline = VPhoneLaunchpadCreationPipeline(options: options,
            bundles: bundles, helper: VPhoneLaunchpadHelperClient(), library: library,
            deviceInitializer: VPhoneLaunchpadDeviceInitializationAdapter.make(bundles: bundles))
        precondition(pipeline.steps.suffix(2) == [.firstBoot, .initializeDevice])
        precondition(!pipeline.isFinished)
        pipeline.start(from: .firstBoot)
        while pipeline.isRunning { try await Task.sleep(for: .milliseconds(1)) }
        precondition(pipeline.failedStep == .initializeDevice && !pipeline.isFinished)
        precondition(pipeline.status(.firstBoot) == .passed && library.starts == 1)
        precondition(bundles.cli.calls.isEmpty, "No config writes before verification succeeds")
        VPhoneDeviceInitialization.shouldFail = false
        pipeline.start(from: pipeline.failedStep!)
        while pipeline.isRunning { try await Task.sleep(for: .milliseconds(1)) }
        precondition(pipeline.isFinished && pipeline.failedStep == nil && pipeline.failure == nil)
        precondition(pipeline.status(.firstBoot) == .passed && library.starts == 1, "Retry must leave first boot untouched")
        precondition(bundles.cli.calls == [["vm", "config", "new-phone", "--unlock-at-startup", "on", "--library-root", root]])
        precondition(bundles.versions.allSatisfy { $0 == "2.9.0-local.abcdef12" })
        precondition(VPhoneLaunchpadGuestSocket.paths == [options.machine.url.appendingPathComponent("vphone.sock").path,
                                                       options.machine.url.appendingPathComponent("vphone.sock").path])

        var baseOptions = options
        baseOptions.name = "base-phone"
        let base = VPhoneLaunchpadCreationPipeline(options: baseOptions,
            bundles: bundles, helper: VPhoneLaunchpadHelperClient(), library: library)
        precondition(base.steps.last == .firstBoot && !base.steps.contains(.initializeDevice))
        base.start(from: .firstBoot)
        while base.isRunning { try await Task.sleep(for: .milliseconds(1)) }
        precondition(base.isFinished && base.failedStep == nil)
        precondition(bundles.cli.calls.count == 1 && VPhoneLaunchpadGuestSocket.paths.count == 2)
        base.start(from: .initializeDevice)
        precondition(!base.isRunning && base.failure != nil, "Disabled hooks must reject explicit retry")

        VPhoneLaunchpadGuestSocket.malformed = true
        pipeline.start(from: .initializeDevice)
        while pipeline.isRunning { try await Task.sleep(for: .milliseconds(1)) }
        precondition(pipeline.failedStep == .initializeDevice && !pipeline.isFinished)
        precondition(bundles.cli.calls.count == 1, "Malformed replies must not enable startup unlock")

        VPhoneLaunchpadGuestSocket.malformed = false
        let other = VPhoneLaunchpadMachinePath(libraryRoot: root + "/other-library", name: options.name)
        try await VPhoneLaunchpadDeviceInitializationAdapter.make(bundles: bundles)(other, "2.10.0", { _ in })
        precondition(VPhoneLaunchpadGuestSocket.paths.last == other.url.appendingPathComponent("vphone.sock").path)
        precondition(bundles.versions.last == "2.10.0")
        precondition(bundles.cli.calls.last == ["vm", "config", other.name, "--unlock-at-startup", "on"] + other.libraryArguments,
                     "Equal names in different libraries must keep their own context")
        print("Creation tests passed: injected/disabled hooks, first boot, isolated retry, 2.9 pinned context, malformed replies, startup unlock")
    }
}
