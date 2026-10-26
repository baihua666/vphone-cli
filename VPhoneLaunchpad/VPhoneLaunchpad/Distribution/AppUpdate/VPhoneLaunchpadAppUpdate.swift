#if VPHONE_CUSTOM_DISTRIBUTION && VPHONE_CUSTOM_APP_UPDATE
import Foundation

nonisolated enum VPhoneLaunchpadAppUpdate {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
    struct Prepared: Sendable {
        let directory: URL
        let application: URL
        let destination: URL
        let requirement: String
    }

    /// The copied App is on the destination volume; the installed App stays untouched.
    @concurrent static func prepare(dmg: URL, destination: URL, revision: Int, baseline: String) async throws -> Prepared {
        let files = FileManager.default
        guard destination.pathExtension == "app", destination.lastPathComponent == "vphone-launchpad.app",
              destination.standardizedFileURL == destination.resolvingSymlinksInPath(),
              files.isWritableFile(atPath: destination.deletingLastPathComponent().path) else {
            throw Failure("当前 App 所在目录不可写或路径不适合自动更新，请将 App 安装到可写的应用程序目录后重试。")
        }
        let current = try command("/usr/bin/codesign", ["-dvv", destination.path])
        guard let team = current.split(separator: "\n").first(where: { $0.hasPrefix("TeamIdentifier=") })?.dropFirst(15),
              !team.isEmpty, team.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw Failure("无法确认当前 App 的签名团队，未更新。")
        }
        let requirement = "anchor apple generic and identifier com.vphone.launchpad and certificate leaf[subject.OU] = \"\(team)\""
        let directory = destination.deletingLastPathComponent().appendingPathComponent(".vphone-update-" + UUID().uuidString)
        try files.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let mount = directory.appendingPathComponent("mount")
        try files.createDirectory(at: mount, withIntermediateDirectories: false)
        var keep = false
        var mounted = false
        defer { if !keep && !mounted { try? files.removeItem(at: directory) } }
        _ = try command("/usr/bin/hdiutil", ["attach", dmg.path, "-readonly", "-nobrowse", "-mountpoint", mount.path])
        mounted = true
        defer { if (try? command("/usr/bin/hdiutil", ["detach", mount.path])) != nil { mounted = false } }
        let source = mount.appendingPathComponent("vphone-launchpad.app")
        let application = directory.appendingPathComponent("vphone-launchpad.app")
        _ = try command("/usr/bin/ditto", [source.path, application.path])
        try validate(application, revision: revision, baseline: baseline, requirement: requirement)
        keep = true
        return Prepared(directory: directory, application: application, destination: destination, requirement: requirement)
    }

    static func validate(_ application: URL, revision: Int, baseline: String, requirement: String) throws {
        _ = try command("/usr/bin/codesign", ["--verify", "--strict", "--deep", "-R=" + requirement, application.path])
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: application.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any]
        guard info?["CFBundleIdentifier"] as? String == "com.vphone.launchpad",
              info?["CFBundleShortVersionString"] as? String == baseline,
              info?["VPhoneDistributionRevision"] as? String == String(revision) else {
            throw Failure("安装包中的 App 身份、官方基线或更新修订不匹配，未替换当前版本。")
        }
        guard let rules = info?["SMPrivilegedExecutables"] as? [String: String],
              let helperRule = rules["com.vphone.launchpad.helper"] else { throw Failure("更新包缺少 Helper 签名规则。") }
        _ = try command("/usr/bin/codesign", ["--verify", "--strict", "-R=" + helperRule,
            application.appendingPathComponent("Contents/Library/LaunchServices/com.vphone.launchpad.helper").path])
    }

    @concurrent static func handoff(_ prepared: Prepared, parent: Int32, report: URL) async throws -> Int32 {
        let script = prepared.directory.appendingPathComponent("install.zsh")
        try installer.write(to: script, atomically: true, encoding: .utf8)
        let log = prepared.directory.appendingPathComponent("install.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path, String(parent), prepared.application.path, prepared.destination.path, prepared.requirement, report.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output; process.standardError = output
        try process.run()
        var handedOff = false
        defer { if !handedOff && process.isRunning { process.terminate() } }
        let ready = prepared.directory.appendingPathComponent("ready")
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: ready.path) {
                handedOff = true
                return process.processIdentifier
            }
            guard process.isRunning else { throw Failure("更新安装进程未就绪；当前 App 保留。详情：\(log.path)") }
            try await Task.sleep(for: .milliseconds(100))
        }
        process.terminate()
        throw Failure("更新安装进程准备超时，当前 App 保留。")
    }

    @discardableResult static func command(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure("更新校验或文件操作失败（\(URL(fileURLWithPath: executable).lastPathComponent)）：" + String(decoding: data, as: UTF8.self))
        }
        return String(decoding: data, as: UTF8.self)
    }
}
#endif
