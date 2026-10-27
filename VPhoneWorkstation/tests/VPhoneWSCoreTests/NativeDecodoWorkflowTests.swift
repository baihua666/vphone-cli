import Foundation
import Testing
@testable import VPhoneWSCore

@Test func nativeProbeReportsHTTPStageWithoutLeakingResponse() throws {
    for (http, connect, exit): (Int, Int, Int32) in [(0, 407, 56), (400, 200, 22), (503, 200, 22)] {
        do {
            _ = try NativeDecodoService.decodeCurl(Data("secret-provider-body\nVPHONE_STATUS:\(http):\(connect)".utf8), exitCode: exit, stage: "代理出口检测")
            Issue.record("Expected HTTP rejection")
        } catch {
            #expect(error.localizedDescription.contains("代理出口检测"))
            #expect(error.localizedDescription.contains(String(connect >= 400 ? connect : http)))
            #expect(!error.localizedDescription.contains("secret-provider-body"))
            #expect(!error.localizedDescription.contains("物理网卡"))
        }
    }
    let body = try NativeDecodoService.decodeCurl(Data("{\"ip\":\"192.0.2.1\"}\nVPHONE_STATUS:200:200".utf8), exitCode: 0, stage: "检测")
    #expect(String(decoding: body, as: UTF8.self) == #"{"ip":"192.0.2.1"}"#)
}

#if VPHONE_CUSTOM_NATIVE_PROXY_WORKFLOW
private actor WorkflowRunner: CLIRunner {
    var saved: NativeDecodoConfiguration?
    var mutations = 0
    var unavailableReads = 0
    func simulateStarting() { unavailableReads = 1 }
    func run(executable: URL, arguments: [String], environment: [String: String]?) async throws -> CLIResult {
        if arguments.contains("--help") { return .init(stdout: "--probe --native-proxy-file", stderr: "", exitCode: 0) }
        if unavailableReads > 0 {
            unavailableReads -= 1
            return .init(stdout: "", stderr: "control socket not ready", exitCode: 64)
        }
        if let flag = arguments.firstIndex(of: "--native-proxy-file") {
            saved = try JSONDecoder().decode(NativeDecodoConfiguration.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[flag + 1])))
            mutations += 1
            if let root = arguments.firstIndex(of: "--library-root") {
                let reference = URL(fileURLWithPath: arguments[root + 1]).appendingPathComponent("a/native-proxy-reference.json")
                try JSONEncoder().encode(arguments[flag + 1]).write(to: reference)
            }
        }
        return .init(stdout: #"{"device":true,"native_proxy_supported":true,"native_proxy_enabled":true,"egress":{"ip":"192.0.2.1","origin":"guest","source":"test","checked_at":"2026-10-27T00:00:00Z"}}"#, stderr: "", exitCode: 0)
    }
}

private actor WorkflowProbe {
    var configs: [NativeDecodoConfiguration] = []
    var fail = false
    func setFailure() { fail = true }
    func run(_ config: NativeDecodoConfiguration) throws -> IPLocation {
        configs.append(config)
        if fail { throw ProxyRouteError("代理出口检测失败：HTTP 407") }
        return try IPLocationLookup.decode(Data(#"{"success":true,"ip":"192.0.2.1","country":"United States","city":"New York City"}"#.utf8), expectedIP: "192.0.2.1")
    }
}

@MainActor private final class WorkflowFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let runner = WorkflowRunner()
    let probe = WorkflowProbe()
    let controller: NativeDecodoController
    let client: VPhoneCLIClient
    init() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a"), withIntermediateDirectories: true)
        let credentialFile = root.appendingPathComponent("credentials.json")
        try Data(#"{"username":"test","password":"test"}"#.utf8).write(to: credentialFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialFile.path)
        client = VPhoneCLIClient(executable: URL(fileURLWithPath: "/cli"), libraryRoot: root.path, runner: runner)
        let probe = self.probe
        controller = NativeDecodoController(client: client, name: "a", probe: .init(
            validate: { _, _ in }, resolve: { _, _ in "192.0.2.2" }, probe: { config, _ in try await probe.run(config) }))
        controller.device = "en1"
        controller.credentialsPath = credentialFile.path
    }
    func cleanup() {
        // Remove only this fixture's unique private configuration directory.
        if let context = try? client.context(name: "a"),
           let reference = try? Data(contentsOf: context.directory.appendingPathComponent("native-proxy-reference.json")),
           let saved = try? JSONDecoder().decode(String.self, from: reference) {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: saved).deletingLastPathComponent())
        }
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor @Test func savingUsesExactlyTheTestedEndpointAndReopensItsSelection() async throws {
    let fixture = try WorkflowFixture(); defer { fixture.cleanup() }
    let city = DecodoLocation(kind: .city, country: "US", city: "New York City", state: "New York")
    await fixture.controller.testDirect(location: city)
    #expect(fixture.controller.canSaveTested(location: city))
    #expect(await fixture.runner.mutations == 0)
    await fixture.runner.simulateStarting()
    await fixture.controller.waitForCore()
    #expect(fixture.controller.supported)
    #expect(fixture.controller.canSaveTested(location: city))
    await fixture.controller.saveTested(location: city)
    #expect(fixture.controller.guestIP == "192.0.2.1")
    #expect(await fixture.runner.mutations == 1)
    let configs = await fixture.probe.configs
    #expect(configs.count == 2)
    #expect(configs[0].port == configs[1].port)
    #expect(configs[0].username == configs[1].username)
    #expect(await fixture.runner.saved?.port == configs[0].port)
    #expect(!fixture.controller.canSaveTested(location: city))
    let reopened = NativeDecodoController(client: fixture.client, name: "a")
    #expect(reopened.configuredLocation(in: [city]) == city)
}

@MainActor @Test func changedSelectionOrFailedRecheckCannotSave() async throws {
    let fixture = try WorkflowFixture(); defer { fixture.cleanup() }
    await fixture.controller.testDirect()
    fixture.controller.zip = "90210"
    #expect(!fixture.controller.canSaveTested(location: nil))
    await fixture.controller.saveTested()
    #expect(await fixture.runner.mutations == 0)
    await fixture.controller.testDirect()
    await fixture.probe.setFailure()
    await fixture.controller.saveTested()
    #expect(await fixture.runner.mutations == 0)
    #expect(fixture.controller.message.contains("407"))
    #expect(!fixture.controller.canSaveTested(location: nil))
}
#else
@MainActor @Test func disabledWorkflowCannotSaveOrExecuteCommands() async {
    let runner = FakeCLIRunner()
    let controller = NativeDecodoController(client: .init(executable: URL(fileURLWithPath: "/cli"), libraryRoot: nil, runner: runner), name: "a")
    #expect(!NativeDecodoController.stagedWorkflowEnabled)
    await controller.saveTested()
    #expect(runner.calls.isEmpty)
}
#endif

#if VPHONE_CUSTOM_NATIVE_PROXY_WORKFLOW && VPHONE_CUSTOM_EMBEDDED_DECODO_CREDENTIALS
@MainActor @Test func embeddedAccountCompletesWorkflowWithoutCredentialFile() async throws {
    let fixture = try WorkflowFixture(); defer { fixture.cleanup() }
    try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("credentials.json"))
    await fixture.controller.testDirect()
    #expect(fixture.controller.canSaveTested(location: nil))
    // Legacy local settings cannot invalidate or replace the embedded account.
    fixture.controller.credentialsPath = "/Users/another-mac/missing.json"
    #expect(fixture.controller.canSaveTested(location: nil))
    await fixture.controller.saveTested()
    #expect(await fixture.runner.mutations == 1)
    #expect(fixture.controller.guestIP == "192.0.2.1")
}
#endif

#if VPHONE_CUSTOM_NATIVE_PROXY_WORKFLOW
@MainActor @Test func guestDetectionCannotHideCandidateFailure() async throws {
    let fixture = try WorkflowFixture(); defer { fixture.cleanup() }
    await fixture.probe.setFailure()
    await fixture.controller.testDirect()
    let failure = fixture.controller.configurationMessage
    #expect(failure?.contains("407") == true)
    #expect(!fixture.controller.canSaveTested(location: nil))
    await fixture.controller.detectGuest()
    #expect(fixture.controller.guestIP == "192.0.2.1")
    #expect(fixture.controller.configurationMessage == failure)
}
#endif

#if VPHONE_CUSTOM_NATIVE_PROXY_WORKFLOW
@MainActor @Test func singleActionTestsAppliesSameEndpointAndVerifiesGuest() async throws {
    let fixture = try WorkflowFixture(); defer { fixture.cleanup() }
    await fixture.controller.rotate()
    let configs = await fixture.probe.configs
    #expect(configs.count == 1)
    #expect(await fixture.runner.saved?.port == configs.first?.port)
    #expect(await fixture.runner.mutations == 1)
    #expect(fixture.controller.guestIP == "192.0.2.1")
    #expect(fixture.controller.message.contains("一致"))
}

@MainActor @Test func singleActionDoesNotApplyWhenProviderDetectionFails() async throws {
    let fixture = try WorkflowFixture(); defer { fixture.cleanup() }
    await fixture.probe.setFailure()
    await fixture.controller.rotate()
    #expect(await fixture.runner.mutations == 0)
    #expect(fixture.controller.guestIP == nil)
    #expect(fixture.controller.message.contains("407"))
}
#endif
