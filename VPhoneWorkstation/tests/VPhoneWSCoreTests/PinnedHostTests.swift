import Testing
import Foundation
@testable import VPhoneWSCore

@MainActor
@Test func launchesEachVMWithItsPinnedHostAndVariant() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let launcher = FakeProcessLauncher(stubPID: 77)
    let runner = FakeCLIRunner()
    let fallback = URL(fileURLWithPath: "/default/vphone-cli")
    let client = VPhoneCLIClient(executable: fallback, libraryRoot: root.path, runner: runner)
    let coordinator = LaunchCoordinator(executable: fallback, libraryRoot: root.path,
        launcher: launcher, client: client, probe: RunningStateProbe(runner: runner))
    for (name, variant) in [("official", "regular"), ("custom", "exp")] {
        let folder = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: [
            "variant": variant, "executablePath": "/\(name)/vphone-cli"])
        try data.write(to: folder.appendingPathComponent(".vphone-ws.json"))
        try VariantStore(libraryRoot: root.path).setVariant(variant, forVM: name)
        try coordinator.launch(name: name)
        #expect(launcher.calls.last?.executable.path == "/\(name)/vphone-cli")
        #expect(launcher.calls.last?.arguments == ["vm", "launch", name,
            "--library-root", root.path, "--variant", variant])
    }
}

@Test func exportResolvesLibraryLinkToRealBundle() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = root.appendingPathComponent("library")
    let real = root.appendingPathComponent("real/phone")
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: library.appendingPathComponent("phone"), withDestinationURL: real)
    let args = VPhoneCommandBuilder(libraryRoot: library.path).exportArgs(name: "phone", out: "/export.tzst")
    #expect(args == ["vm", "export", "phone", "-o", "/export.tzst", "--library-root",
                    real.resolvingSymlinksInPath().deletingLastPathComponent().path])
}

@MainActor
@Test func launchesModernPinnedHostWithoutLegacyVariant() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("modern")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: ["executablePath": "/modern/vphone-cli"])
    try data.write(to: folder.appendingPathComponent(".vphone-ws.json"))
    let launcher = FakeProcessLauncher(stubPID: 77)
    let runner = FakeCLIRunner()
    let fallback = URL(fileURLWithPath: "/default/vphone-cli")
    let client = VPhoneCLIClient(executable: fallback, libraryRoot: root.path, runner: runner)
    let coordinator = LaunchCoordinator(executable: fallback, libraryRoot: root.path,
        launcher: launcher, client: client, probe: RunningStateProbe(runner: runner))
    try coordinator.launch(name: "modern")
    #expect(launcher.calls.last?.executable.path == "/modern/vphone-cli")
    #expect(launcher.calls.last?.arguments == ["vm", "launch", "modern", "--library-root", root.path])
}

@Test func readinessUsesConfiguredExecutableOutsidePATH() async {
    let checks = await HostReadiness(runner: FakeCLIRunner(), cliPath: "/bin/echo").runAll()
    #expect(checks.first?.status == .ok)
    #expect(checks.first?.detail == "/bin/echo")
}
