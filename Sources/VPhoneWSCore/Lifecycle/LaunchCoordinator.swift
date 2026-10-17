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
        let disk = URL(fileURLWithPath: libraryRoot ?? AppEnvironment.defaultLibraryRoot())
            .appendingPathComponent(name).resolvingSymlinksInPath()
        var argv = ["vm", "launch", name]
        if libraryRoot != nil { argv += ["--library-root", disk.deletingLastPathComponent().path] }
        let settings = VariantStore(libraryRoot: libraryRoot ?? AppEnvironment.defaultLibraryRoot())
        if let variant = settings.variant(forVM: name) { argv += ["--variant", variant] }
        let host = settings.executablePath(forVM: name).map { URL(fileURLWithPath: $0) } ?? executable
        _ = try launcher.launch(executable: host, arguments: argv, environment: nil)
    }

    public func stop(name: String) async throws {
        let root = libraryRoot ?? AppEnvironment.defaultLibraryRoot()
        let config = URL(fileURLWithPath: "\(root)/\(name)/config.plist").resolvingSymlinksInPath().path
        // Legacy CLI stop targets lsof's XPC disk holder. Signal the AppKit host
        // instead so its own shutdown handler flushes and stops the VM.
        guard let pid = await probe.firstPID(commandContaining: "--config \(config)") else { return }
        guard kill(pid, SIGINT) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        for _ in 0..<100 {
            if !(try await probe.isRunning(diskImagePath: "\(root)/\(name)/Disk.img")) { return }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw VPhoneCLIError.nonZeroExit(code: 1, stderr: "VM is still stopping; export is not safe yet.")
    }

    /// Bring the VM's GUI window forward. The window belongs to the
    /// `vphone-cli --config …/config.plist` process — NOT the Virtualization XPC
    /// helper that holds Disk.img — so match on the config path, not lsof.
    public func showScreen(name: String) async {
        let root = libraryRoot ?? AppEnvironment.defaultLibraryRoot()
        let configPath = URL(fileURLWithPath: "\(root)/\(name)/config.plist").resolvingSymlinksInPath().path
        guard let pid = await probe.firstPID(commandContaining: configPath),
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.unhide()
        // macOS 14+ activation is cooperative: the active app (us) must yield to
        // the target, otherwise its own activate() is ignored.
        NSApp.yieldActivation(to: app)
        app.activate()
    }
}
