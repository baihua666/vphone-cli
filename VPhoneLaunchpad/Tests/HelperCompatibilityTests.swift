import Foundation

// Compile the real client; only replace administrator prompts and XPC replies.
struct VPhoneLaunchpadError: LocalizedError {
    let message: String
    let detail: String?
    init(_ message: String, detail: String? = nil) { self.message = message; self.detail = detail }
    var errorDescription: String? { message }
}

final class HelperInstallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

@main
@MainActor
struct HelperCompatibilityTests {
    typealias Compatibility = VPhoneLaunchpadHelperCompatibility
    typealias Client = VPhoneLaunchpadHelperClient

    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let installed = root.appendingPathComponent("installed-helper")
        let job = root.appendingPathComponent("helper.plist")
        let counter = HelperInstallCounter()

        func replace(_ name: String?) throws {
            if FileManager.default.fileExists(atPath: installed.path) { try FileManager.default.removeItem(at: installed) }
            if let name { try FileManager.default.copyItem(at: root.appendingPathComponent(name), to: installed) }
        }
        func environment(_ bundled: String = "current") -> Compatibility {
            Compatibility(
                bundledHelper: root.appendingPathComponent(bundled), installedHelper: installed,
                job: job, requirement: "identifier \"com.vphone.test.helper\""
            )
        }
        func client(_ bundled: String = "current", probe: (@MainActor () async throws -> String)? = nil) -> Client {
            Client(installation: environment(bundled), versionProbe: probe ?? {
                Compatibility.version(at: installed) ?? "unknown"
            }, blessHelper: { counter.increment() })
        }
        func expectRefused(_ client: Client) async {
            let before = counter.value
            do { try await client.install(); preconditionFailure("Expected installation to be refused") }
            catch { precondition(counter.value == before, "Refusal must precede administrator approval") }
        }

        // Numeric comparisons do not treat 9 as newer than 15 or accept junk.
        precondition(Compatibility.compare("9", "15") == .orderedAscending)
        precondition(Compatibility.compare("21", "15") == .orderedDescending)
        precondition(Compatibility.compare("15.0", "15") == .orderedSame)
        precondition(Compatibility.compare("15.10", "15.2") == .orderedDescending)
        for invalid in ["", "?", "15-local", "15..1", "15.", "-1", " 15", "+15", "１5", "1.2.3.4", String(repeating: "9", count: 100)] {
            precondition(Compatibility.compare(invalid, "15") == nil)
            precondition(!Compatibility.isCompatible(invalid))
        }
        try Data().write(to: job)

        // Same build, different bytes (including rebuild/re-sign differences).
        try replace("rebuilt")
        let rebuiltBytes = try Data(contentsOf: installed)
        let bundledBytes = try Data(contentsOf: environment().bundledHelper)
        precondition(rebuiltBytes != bundledBytes)
        let rebuilt = client()
        precondition(rebuilt.state == .unknown, "Presence alone must not mark an unverified peer ready")
        await rebuilt.refresh()
        precondition(rebuilt.state == .ready("15"))
        try await rebuilt.install()
        precondition(counter.value == 0)

        // Newer installed helper and an older compatible helper are both reused.
        try replace("newer")
        let newerBytes = try Data(contentsOf: installed)
        let newer = client()
        await newer.refresh()
        precondition(newer.state == .ready("21"))
        try await newer.install()
        precondition(counter.value == 0)
        let retainedBytes = try Data(contentsOf: installed)
        precondition(retainedBytes == newerBytes)
        try replace("current")
        let olderCompatible = client("newer")
        await olderCompatible.refresh()
        precondition(olderCompatible.state == .ready("15"))
        try await olderCompatible.install()
        precondition(counter.value == 0)

        // XPC errors must not turn into outdated or request a replacement.
        for fixture in ["newer", "old"] {
            try replace(fixture)
            let failed = client(probe: { throw VPhoneLaunchpadError("The helper did not answer.") })
            await failed.refresh()
            guard case .unavailable = failed.state else { preconditionFailure("Expected unavailable") }
            await expectRefused(failed)
        }

        // A stale running process, a missing job, and invalid metadata are errors.
        try replace("newer")
        let stale = client(probe: { "15" })
        await stale.refresh()
        guard case .unavailable = stale.state else { preconditionFailure("Expected stale peer rejection") }
        await expectRefused(stale)
        try FileManager.default.removeItem(at: job)
        let missingJob = client()
        await missingJob.refresh()
        guard case .unavailable = missingJob.state else { preconditionFailure("Expected missing job rejection") }
        await expectRefused(missingJob)
        try Data().write(to: job)
        try replace("malformed")
        let malformed = client()
        await malformed.refresh()
        guard case .unavailable = malformed.state else { preconditionFailure("Expected invalid version rejection") }
        await expectRefused(malformed)

        // Real static signature verification remains mandatory.
        try replace("current")
        var wrongIdentity = environment()
        wrongIdentity.requirement = "identifier \"com.vphone.wrong.helper\""
        let untrusted = Client(installation: wrongIdentity, versionProbe: {
            preconditionFailure("Untrusted file must be rejected before XPC")
        }, blessHelper: { counter.increment() })
        await untrusted.refresh()
        guard case .unavailable = untrusted.state else { preconditionFailure("Expected signature rejection") }
        await expectRefused(untrusted)
        var damaged = try Data(contentsOf: installed)
        damaged[1024] ^= 1
        try damaged.write(to: installed)
        let corrupt = client()
        await corrupt.refresh()
        guard case .unavailable = corrupt.state else { preconditionFailure("Expected corrupt signature rejection") }
        await expectRefused(corrupt)

        // An upgrade during the XPC await must not allow a subsequent downgrade.
        try replace("old")
        let raced = client(probe: { try replace("newer"); return "14" })
        await expectRefused(raced)
        precondition(Compatibility.version(at: installed) == "21")
        precondition(counter.value == 0)
        do { try environment().requireUpgrade(); preconditionFailure("Disk downgrade must be refused") }
        catch {}

        // First installation and a genuine required upgrade still work and
        // verify the resulting file and running version after blessing.
        for initial in [nil, "old"] as [String?] {
            try replace(initial)
            let install = Client(installation: environment(), versionProbe: {
                Compatibility.version(at: installed) ?? "unknown"
            }, blessHelper: {
                counter.increment()
                if FileManager.default.fileExists(atPath: installed.path) { try FileManager.default.removeItem(at: installed) }
                try FileManager.default.copyItem(at: root.appendingPathComponent("current"), to: installed)
            })
            await install.refresh()
            precondition(install.state == (initial == nil ? .notInstalled : .outdated(installed: "14", bundled: "15")))
            try await install.install()
            precondition(install.state == .ready("15"))
        }
        precondition(counter.value == 2)

        try replace("old")
        let failedUpgrade = client()
        do { try await failedUpgrade.install(); preconditionFailure("Expected post-install verification failure") }
        catch {}
        precondition(counter.value == 3, "A failed post-install handshake must be reported")

        var unconfigured = environment()
        unconfigured.requirement = nil
        let noTeam = Client(installation: unconfigured, blessHelper: { counter.increment() })
        await noTeam.refresh()
        precondition(noTeam.state == .unconfigured)
        await expectRefused(noTeam)
        print("HelperCompatibilityTests passed: reuse, newer/older builds, downgrade guards, upgrade races, signatures, XPC failures, install and upgrade")
    }
}
