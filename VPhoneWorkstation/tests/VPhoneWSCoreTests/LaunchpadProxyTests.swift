import Foundation
import Testing
@testable import VPhoneWSCore

@Test func launchpadBindingWinsOverWorkstationAndChecksOtherLibraries() throws {
    let f = try ClashFixture(); defer { f.cleanup() }
    let store = f.root.appendingPathComponent("Bundles")
    let machine = f.context.directory
    func bind(_ directory: URL, _ version: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent("config.plist"))
        try JSONSerialization.data(withJSONObject: ["bundle": version]).write(to: directory.appendingPathComponent("launchpad.json"))
    }
    try bind(machine, "2.8.0-local.aaaaaaaa")
    try Data(#"{"executablePath":"/stale/vphone-cli"}"#.utf8).write(to: machine.appendingPathComponent(".vphone-ws.json"))
    let otherRoot = f.root.appendingPathComponent("second-library")
    let peer = otherRoot.appendingPathComponent("same-name")
    try bind(peer, "2.8.0-local.bbbbbbbb")
    let context = try VMCommandContext(name: "a", executable: URL(fileURLWithPath: "/wrong"),
        libraryRoot: machine.deletingLastPathComponent().path, launchpadStore: store, isolationRoots: [otherRoot.path])
    #expect(context.executable.path == store.appendingPathComponent("2.8.0-local.aaaaaaaa/VPhone.bundle/Contents/MacOS/vphone-cli").path)
    try context.validateProxyIsolation()
    try bind(peer, "2.8.0-local.aaaaaaaa")
    #expect(throws: (any Error).self) { try context.validateProxyIsolation() }
    try bind(peer, "../../outside")
    #expect(throws: (any Error).self) { try context.validateProxyIsolation() }
    try bind(machine, "2.8.0-local.cccccccc")
    #expect(throws: (any Error).self) { try context.validateProxyIsolation() }
}

actor ProxyNetworkRunner: CLIRunner {
    var calls: [[String]] = []
    var attachment = "tunnel"
    var failsProbe = false
    func setAttachment(_ value: String) { attachment = value }
    func failProbe() { failsProbe = true }
    func run(executable: URL, arguments: [String], environment: [String: String]?) async throws -> CLIResult {
        calls.append(arguments)
        if arguments.contains("--help") { return CLIResult(stdout: "--probe", stderr: "", exitCode: 0) }
        var result: [String: Any] = ["device": true, "attachment": attachment]
        if arguments.contains("--probe") {
            if failsProbe { result["egress_error"] = "proxy authentication refused" }
            else { result["egress"] = ["ip": "203.0.113.9", "origin": "guest", "source": "test", "checked_at": "2026-10-22"] }
        }
        return CLIResult(stdout: String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self), stderr: "", exitCode: 0)
    }
}

@MainActor @Test func decodoControllerReadsWithoutMutationThenConfiguresAndRotates() async throws {
    let f = try ClashFixture(); defer { f.cleanup() }
    let runner = ProxyNetworkRunner()
    let client = VPhoneCLIClient(executable: f.context.executable, libraryRoot: f.context.libraryRoot, runner: runner)
    let controller = DecodoProxyController(client: client, proxy: f.service, name: "a", lookupLocation: { _ in throw ProxyRouteError("test offline") }, lookupProvider: { _, _ in throw ProxyRouteError("test offline") })
    await controller.refresh()
    #expect(await f.transport.calls.allSatisfy { $0.hasPrefix("GET") })
    #expect(await runner.calls.isEmpty)
    controller.username = "test"; controller.password = "test-only"; controller.zip = "10001"
    await controller.apply(rotate: false)
    #expect(controller.egress?.origin == "guest")
    let first = try #require(controller.session)
    await runner.failProbe()
    await controller.apply(rotate: true)
    #expect(controller.session?.id != first.id)
    #expect(controller.egress == nil)
    #expect(controller.message.contains("规则已生效"))
    #expect(controller.message.contains("检测失败"))
    #expect(try String(contentsOf: f.source, encoding: .utf8).contains("PROCESS-PATH,/other/vphone-vm,US"))
}

@MainActor @Test func decodoControllerRefusesNonTunnelBeforeProxyWrites() async throws {
    let f = try ClashFixture(); defer { f.cleanup() }
    let runner = ProxyNetworkRunner(); await runner.setAttachment("nat")
    let client = VPhoneCLIClient(executable: f.context.executable, libraryRoot: f.context.libraryRoot, runner: runner)
    let controller = DecodoProxyController(client: client, proxy: f.service, name: "a", lookupLocation: { _ in throw ProxyRouteError("test offline") }, lookupProvider: { _, _ in throw ProxyRouteError("test offline") })
    await controller.refresh()
    controller.username = "test"; controller.password = "test-only"; controller.zip = "10001"
    await controller.apply(rotate: false)
    #expect(await f.transport.calls.allSatisfy { $0.hasPrefix("GET") })
    #expect(controller.session == nil)
    #expect(controller.message.contains("不是 tunnel"))
}
