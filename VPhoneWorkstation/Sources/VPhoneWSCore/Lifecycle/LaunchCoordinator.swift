import Foundation
import AppKit

@MainActor
public final class LaunchCoordinator {
    private let executable: URL
    private let libraryRoot: String?
    private let launcher: ProcessLauncher
    private let client: VPhoneCLIClient
    private let probe: RunningStateProbe

    public init(
        executable: URL, libraryRoot: String?, launcher: ProcessLauncher,
        client: VPhoneCLIClient, probe: RunningStateProbe
    ) {
        self.executable = executable
        self.libraryRoot = libraryRoot
        self.launcher = launcher
        self.client = client
        self.probe = probe
    }

    public func launch(name: String) throws {
        let context = try client.context(name: name)
        var argv = context.arguments("launch")
        if let variant = context.variant { argv += ["--variant", variant] }
        _ = try launcher.launch(executable: context.executable, arguments: argv, environment: nil)
    }

    public func stop(name: String) async throws {
        let context = try client.context(name: name)
        let config = context.directory.appendingPathComponent("config.plist").path
        let host = context.executable.deletingLastPathComponent().appendingPathComponent("vphone-vm")
        if FileManager.default.isExecutableFile(atPath: host.path) {
            // The split-host CLI knows how to stop vphone-vm rather than its XPC service.
            try await client.stop(name: name)
        } else {
            // Legacy compatibility: signal the AppKit host, never the XPC disk holder.
            guard let pid = await probe.firstPID(commandContaining: "--config \(config)") else { return }
            guard kill(pid, SIGINT) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        for _ in 0..<100 {
            if !(try await probe.isRunning(diskImagePath: context.directory.appendingPathComponent("Disk.img").path)) { return }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw VPhoneCLIError.nonZeroExit(code: 1, stderr: "VM is still stopping; export is not safe yet.")
    }

    public func showScreen(name: String) async {
        guard let context = try? client.context(name: name) else { return }
        let config = context.directory.appendingPathComponent("config.plist").path
        guard let pid = await probe.firstPID(commandContaining: config),
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.unhide()
        NSApp.yieldActivation(to: app)
        app.activate()
    }
}
