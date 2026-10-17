import Foundation
import Testing
@testable import VPhoneWSCore

@Test func instanceOperationsUsePinnedExecutableAndRealName() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = root.appendingPathComponent("library")
    let real = root.appendingPathComponent("real/actual")
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: library.appendingPathComponent("alias"), withDestinationURL: real)
    try Data(#"{"executablePath":"/pinned/vphone-cli"}"#.utf8).write(to: real.appendingPathComponent(".vphone-ws.json"))
    let runner = FakeCLIRunner()
    let client = VPhoneCLIClient(executable: URL(fileURLWithPath: "/default/cli"), libraryRoot: library.path, runner: runner)
    let context = try client.context(name: "alias")
    let args = ["vm", "config", "actual", "--cpu", "6", "--library-root", real.deletingLastPathComponent().resolvingSymlinksInPath().path]
    runner.stub(arguments: args, result: CLIResult(stdout: "", stderr: "", exitCode: 0))
    try await client.setConfig(name: "alias", cpu: 6, memoryMB: nil, network: nil)
    #expect(runner.calls.last?.executable.path == "/pinned/vphone-cli")
    #expect(runner.calls.last?.arguments == args)
    #expect(context.arguments("export", options: ["-o", "/out"])[2] == "actual")
    await #expect(throws: (any Error).self) { try await client.delete(name: "alias") }
    #expect(runner.calls.count == 1)
}

@Test func malformedBindingDoesNotFallBackAndNamesCannotEscapeLibrary() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appendingPathComponent("a"), withIntermediateDirectories: true)
    try Data("broken".utf8).write(to: root.appendingPathComponent("a/.vphone-ws.json"))
    let client = VPhoneCLIClient(executable: URL(fileURLWithPath: "/default/cli"), libraryRoot: root.path, runner: FakeCLIRunner())
    #expect(throws: (any Error).self) { try client.context(name: "a") }
    #expect(throws: (any Error).self) { try client.context(name: "../outside") }
}

@Test func networkProbeUsesGuestResultAndReportsOldRuntime() async throws {
    let runner = FakeCLIRunner()
    let client = VPhoneCLIClient(executable: URL(fileURLWithPath: "/cli"), libraryRoot: nil, runner: runner)
    runner.stub(arguments: ["vm", "network", "a", "--help"], result: CLIResult(stdout: "--probe", stderr: "", exitCode: 0))
    runner.stub(arguments: ["vm", "network", "a", "--json", "--probe"], result: CLIResult(stdout: #"{"device":true,"guest_addresses":["en0 192.168.127.3"],"egress":{"ip":"1.1.1.1","source":"https://api.ipify.org?format=json","origin":"guest","checked_at":"2026-10-17T00:00:00Z"}}"#, stderr: "", exitCode: 0))
    let result = try await client.networkStatus(name: "a", probe: true)
    #expect(result.egress?.ip == "1.1.1.1")
    #expect(result.guestAddresses == ["en0 192.168.127.3"])
    #expect(result.guestInterfaceIPv4 == "192.168.127.3")
    runner.stub(arguments: ["vm", "network", "a", "--help"], result: CLIResult(stdout: "--link", stderr: "", exitCode: 0))
    runner.stub(arguments: ["vm", "network", "a", "--json"], result: CLIResult(stdout: #"{"device":true,"link":"up"}"#, stderr: "", exitCode: 0))
    let old = try await client.networkStatus(name: "a", probe: true)
    #expect(old.egress == nil)
    #expect(old.egressError?.contains("不支持") == true)
    #expect(runner.calls.last?.arguments.last == "--json")
}

@Test func networkRejectsHostMeasurementAndPreservesGuestFailure() async throws {
    let runner = FakeCLIRunner()
    let client = VPhoneCLIClient(executable: URL(fileURLWithPath: "/cli"), libraryRoot: nil, runner: runner)
    let args = ["vm", "network", "a", "--json"]
    runner.stub(arguments: args, result: CLIResult(stdout: #"{"device":true,"egress":{"ip":"1.1.1.1","source":"host","origin":"host","checked_at":"now"}}"#, stderr: "", exitCode: 0))
    await #expect(throws: (any Error).self) { _ = try await client.networkStatus(name: "a") }
    runner.stub(arguments: args, result: CLIResult(stdout: #"{"device":true,"egress_error":"guest timeout"}"#, stderr: "", exitCode: 0))
    let result = try await client.networkStatus(name: "a")
    #expect(result.egress == nil)
    #expect(result.egressError == "guest timeout")
}

@MainActor @Test func modernStopUsesPinnedCLIAndWaitsForDiskRelease() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let machine = root.appendingPathComponent("phone")
    let runtime = root.appendingPathComponent("runtime")
    try FileManager.default.createDirectory(at: machine, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
    let host = runtime.appendingPathComponent("vphone-vm")
    try Data().write(to: host)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: host.path)
    let exe = runtime.appendingPathComponent("vphone-cli")
    try JSONSerialization.data(withJSONObject: ["executablePath": exe.path]).write(to: machine.appendingPathComponent(".vphone-ws.json"))
    let runner = FakeCLIRunner()
    let client = VPhoneCLIClient(executable: URL(fileURLWithPath: "/fallback/cli"), libraryRoot: root.path, runner: runner)
    let context = try client.context(name: "phone")
    runner.stub(arguments: context.arguments("stop"), result: CLIResult(stdout: "stopped", stderr: "", exitCode: 0))
    runner.stub(arguments: ["-t", "--", context.directory.appendingPathComponent("Disk.img").path], result: CLIResult(stdout: "", stderr: "", exitCode: 1))
    let coordinator = LaunchCoordinator(executable: exe, libraryRoot: root.path, launcher: FakeProcessLauncher(stubPID: 1), client: client, probe: RunningStateProbe(runner: runner))
    try await coordinator.stop(name: "phone")
    #expect(runner.calls.first?.executable == exe)
    #expect(runner.calls.first?.arguments == context.arguments("stop"))
    #expect(runner.calls.count == 2)
}
