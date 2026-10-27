import Foundation
import Testing
@testable import VPhoneWSCore

@MainActor @Test func nativeDetectionClearsPreviousIPAndShowsStoppedGuestFailure() async {
    let runner = FakeCLIRunner()
    let client = VPhoneCLIClient(executable: URL(fileURLWithPath: "/cli"), libraryRoot: nil, runner: runner)
    let controller = NativeDecodoController(client: client, name: "a")
    let help = ["vm", "network", "a", "--help"]
    let probe = ["vm", "network", "a", "--json", "--probe"]
    runner.stub(arguments: help, result: CLIResult(stdout: "--probe", stderr: "", exitCode: 0))
    let success = CLIResult(stdout: #"{"device":true,"egress":{"ip":"192.0.2.1","origin":"guest","source":"ipify","checked_at":"2026-10-27T00:00:00Z"}}"#, stderr: "", exitCode: 0)
    runner.stub(arguments: probe, result: success)
    await controller.detectGuest()
    #expect(controller.guestIP == "192.0.2.1")

    runner.stub(arguments: probe, result: CLIResult(stdout: "", stderr: "a is not running, or its control socket does not answer.", exitCode: 64))
    await controller.detectGuest()
    #expect(controller.guestIP == nil)
    #expect(controller.message.contains("not running"))
    #expect(controller.message.contains("64"))
    #expect(!controller.busy)

    runner.stub(arguments: probe, result: success)
    await controller.detectGuest()
    #expect(controller.guestIP == "192.0.2.1")
    #expect(controller.message == "检测完成，未修改代理。")
    #expect(runner.calls.allSatisfy { $0.arguments == help || $0.arguments == probe })
}

@Test func nativeModeUsesExistingDecodoParameterRulesAndSeparateFiles() throws {
    let fixture = try ClashFixture(); defer { fixture.cleanup() }
    let credentials = NativeDecodoService.Credentials(username: "test", password: "test")
    let residential = try NativeDecodoService.configuration(context: fixture.context, credentials: credentials,
        isp: false, city: "", zip: "10001", interface: "wifi")
    let next = try NativeDecodoService.configuration(context: fixture.context, credentials: credentials,
        isp: false, city: "", zip: "10001", interface: "wifi")
    #expect(residential.username != next.username)
    #expect(residential.username.hasSuffix("-sessionduration-5"))
    let isp = try NativeDecodoService.configuration(context: fixture.context, credentials: credentials,
        isp: true, city: "New York", zip: "", interface: "wifi")
    #expect(isp.username == "user-test-country-us-city-new_york_city")
    #expect((10001...63000).contains(isp.port))
    #expect(!NativeDecodoService.validAddress("198.18.0.23"))
    #expect(!NativeDecodoService.validAddress("example.com"))
    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(isp)) as! [String: Any]
    #expect(Set(json.keys) == ["host", "address", "port", "username", "password", "interface", "dnsAddress"])
}

@Test func nativeCapabilityIsOptionalForExistingCores() throws {
    let status = try JSONDecoder().decode(VMNetworkStatus.self, from: Data(#"{"device":true,"link":"up"}"#.utf8))
    #expect(status.nativeProxySupported == nil)
    let next = try JSONDecoder().decode(VMNetworkStatus.self, from: Data(#"{"device":true,"native_proxy_supported":true,"native_proxy_enabled":false}"#.utf8))
    #expect(next.nativeProxySupported == true)
    #expect(next.nativeProxyEnabled == false)
}

@Test func unsupportedCoreCannotReceiveMutation() async throws {
    let fixture = try ClashFixture(); defer { fixture.cleanup() }
    let runner = ProxyNetworkRunner()
    let client = VPhoneCLIClient(executable: fixture.context.executable, libraryRoot: fixture.context.libraryRoot, runner: runner)
    do {
        try await client.setNativeProxy(name: "a", path: "/not-read.json")
        Issue.record("Old core must reject native proxy")
    } catch {}
    #expect(await runner.calls.allSatisfy { !$0.contains("--native-proxy-file") })
}

@Test func nativeCatalogUsesSelectedRegionAndExcludesBoundPorts() throws {
    let fixture = try ClashFixture(); defer { fixture.cleanup() }
    let credentials = NativeDecodoService.Credentials(username: "test", password: "test")
    let selections: [DecodoLocation] = [
        .random,
        .init(kind: .country, country: "FR", city: "", state: ""),
        .init(kind: .state, country: "US", city: "", state: "New York"),
        .init(kind: .city, country: "US", city: "Boston", state: "Massachusetts")
    ]
    for selected in selections {
        let config = try NativeDecodoService.configuration(context: fixture.context, credentials: credentials,
            isp: true, city: "ignored", zip: "", interface: "wifi", location: selected,
            occupied: Set(10001...63000).subtracting([32123]))
        #expect(config.username == "user-test" + selected.suffix)
        #expect(config.port == 32123)
        let file = fixture.context.directory.appendingPathComponent("test-native.json")
        try JSONEncoder().encode(config).write(to: file)
        try JSONEncoder().encode(file.path).write(to: fixture.context.directory.appendingPathComponent("native-proxy-reference.json"))
        #expect(try NativeDecodoService.occupiedPorts(context: fixture.context).contains(32123))
    }
}
