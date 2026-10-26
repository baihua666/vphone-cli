import Foundation

@main struct AppUpdateTests {
    static func main() async throws {
        let dmg = URL(fileURLWithPath: CommandLine.arguments[1])
        let destination = URL(fileURLWithPath: CommandLine.arguments[2])
        let prepared = try await VPhoneLaunchpadAppUpdate.prepare(dmg: dmg, destination: destination, revision: 6, baseline: "2.13.4")
        defer { try? FileManager.default.removeItem(at: prepared.directory) }
        precondition(prepared.application != destination)
        precondition(prepared.directory.deletingLastPathComponent() == destination.deletingLastPathComponent())
        try VPhoneLaunchpadAppUpdate.validate(prepared.application, revision: 6, baseline: "2.13.4", requirement: prepared.requirement)
        for hasReplacement in [false, true] {
            let root = prepared.directory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            let target = root.appendingPathComponent("target.app")
            try "old".write(to: root.appendingPathComponent("previous.app"), atomically: true, encoding: .utf8)
            if hasReplacement { try "new".write(to: target, atomically: true, encoding: .utf8) }
            let rollback = root.appendingPathComponent("rollback.zsh")
            let prefix = VPhoneLaunchpadAppUpdate.installer.components(separatedBy: "trap failed ZERR")[0]
            try (prefix + "\nmoved=1\nfailed\n").write(to: rollback, atomically: true, encoding: .utf8)
            try VPhoneLaunchpadAppUpdate.command("/bin/zsh", [rollback.path, String(ProcessInfo.processInfo.processIdentifier), "unused", target.path, "unused", root.appendingPathComponent("error.txt").path])
            let restored = try String(contentsOf: target, encoding: .utf8)
            precondition(restored == "old")
        }
        do {
            try VPhoneLaunchpadAppUpdate.validate(prepared.application, revision: 7, baseline: "2.13.4", requirement: prepared.requirement)
            fatalError("accepted a wrong revision")
        } catch {}
        do {
            try VPhoneLaunchpadAppUpdate.validate(prepared.application, revision: 6, baseline: "2.13.4", requirement: "identifier another.app")
            fatalError("accepted a wrong signer identity")
        } catch {}
        let info = prepared.application.appendingPathComponent("Contents/Info.plist")
        var data = try Data(contentsOf: info); data.append(Data("\n".utf8)); try data.write(to: info)
        do {
            try VPhoneLaunchpadAppUpdate.validate(prepared.application, revision: 6, baseline: "2.13.4", requirement: prepared.requirement)
            fatalError("accepted a tampered App")
        } catch {}
        let script = prepared.directory.appendingPathComponent("installer.zsh")
        try VPhoneLaunchpadAppUpdate.installer.write(to: script, atomically: true, encoding: .utf8)
        try VPhoneLaunchpadAppUpdate.command("/bin/zsh", ["-n", script.path])
        let child = Process(); child.executableURL = URL(fileURLWithPath: "/bin/zsh")
        child.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), prepared.application.path, destination.path, prepared.requirement, prepared.directory.appendingPathComponent("failure.txt").path]
        child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
        try child.run(); child.waitUntilExit()
        precondition(child.terminationStatus != 0)
        precondition(!FileManager.default.fileExists(atPath: prepared.directory.appendingPathComponent("ready").path))
        precondition(FileManager.default.fileExists(atPath: destination.path))
        print("PASS: real signed DMG staging, revision/identity rejection, tamper rejection, installer validation failure preserves installed App")
    }
}
