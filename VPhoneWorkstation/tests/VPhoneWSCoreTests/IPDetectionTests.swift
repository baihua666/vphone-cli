import Foundation
import Testing
@testable import VPhoneWSCore

@Test func locationRequiresMatchingIPAndHandlesMissingFields() throws {
    let data = Data(#"{"success":true,"ip":"203.0.113.9","country":"United States","region":"New York","city":"New York"}"#.utf8)
    let result = try IPLocationLookup.decode(data, expectedIP: "203.0.113.9")
    #expect(result.area == "United States · New York · New York")
    #expect(result.postal == nil)
    #expect(throws: (any Error).self) { try IPLocationLookup.decode(data, expectedIP: "203.0.113.10") }
    #expect(throws: (any Error).self) {
        try IPLocationLookup.decode(Data(#"{"success":false,"message":"reserved range"}"#.utf8), expectedIP: "203.0.113.9")
    }
}

@MainActor @Test func detectionNeverWritesProxyAndClearsStaleResults() async throws {
    let f = try ClashFixture(); defer { f.cleanup() }
    let before = try Data(contentsOf: f.source)
    let runner = ProxyNetworkRunner()
    let client = VPhoneCLIClient(executable: f.context.executable, libraryRoot: f.context.libraryRoot, runner: runner)
    let controller = DecodoProxyController(client: client, proxy: f.service, name: "a", lookupLocation: { ip in
        #expect(ip == "203.0.113.9")
        throw ProxyRouteError("offline")
    }, lookupProvider: { _, _ in throw ProxyRouteError("test offline") })
    // Detection does not require a configured route, and cannot apply an edited form.
    controller.zip = "90210"
    await controller.detectCurrentIP()
    #expect(controller.egress?.ip == "203.0.113.9")
    #expect(controller.location == nil)
    #expect(controller.locationMessage.contains("查询失败"))
    #expect(await f.transport.calls.isEmpty)
    #expect(await runner.calls.allSatisfy { $0.contains("network") && !$0.contains("config") })
    #expect(try Data(contentsOf: f.source) == before)
    await runner.failProbe()
    await controller.detectCurrentIP()
    #expect(controller.egress == nil)
    #expect(controller.location == nil)
    #expect(controller.message.contains("检测失败"))
    #expect(await f.transport.calls.isEmpty)
}

@Test func alternateLocationSchemaKeepsISPAndRejectsWrongIP() throws {
    let data = Data(#"{"success":true,"ip":"9.249.113.10","country":"United States","city":"Washington","isp":"Verizon Business","asn":"AS5650"}"#.utf8)
    let result = try IPLocationLookup.decode(data, expectedIP: "9.249.113.10")
    #expect(result.connection?.isp == "Verizon Business")
    #expect(result.connection?.asn == 5650)
    #expect(result.postal == nil)
    #expect(throws: (any Error).self) { try IPLocationLookup.decode(data, expectedIP: "9.249.113.1") }
}

@Test func decodoLocationKeepsCityPostalAndRejectsDifferentEgress() throws {
    let data = Data(#"{"proxy":{"ip":"203.0.113.9"},"country":{"name":"United States"},"city":{"name":"New York City","state":"New York","zip_code":"10004"},"isp":{"isp":"RCN","asn":6079}}"#.utf8)
    let result = try IPLocationLookup.decodeDecodo(data, expectedIP: "203.0.113.9")
    #expect(result.source == "Decodo / IPInfo")
    #expect(result.postal == "10004")
    #expect(result.city == "New York City")
    #expect(throws: (any Error).self) { try IPLocationLookup.decodeDecodo(data, expectedIP: "203.0.113.10") }
}

@MainActor @Test func comparisonKeepsBothSourcesAndDoesNotMergePostal() async throws {
    let f = try ClashFixture(); defer { f.cleanup() }
    let runner = ProxyNetworkRunner()
    let client = VPhoneCLIClient(executable: f.context.executable, libraryRoot: f.context.libraryRoot, runner: runner)
    let controller = DecodoProxyController(client: client, proxy: f.service, name: "a", lookupLocation: { ip in
        try IPLocationLookup.decode(Data(#"{"success":true,"ip":"203.0.113.9","country":"United States","region":"New Jersey","city":"Princeton"}"#.utf8), expectedIP: ip)
    }, lookupProvider: { _, ip in
        try IPLocationLookup.decodeDecodo(Data(#"{"proxy":{"ip":"203.0.113.9"},"country":{"name":"United States"},"city":{"name":"New York City","state":"New York","zip_code":"10004"}}"#.utf8), expectedIP: ip)
    })
    await controller.detectCurrentIP()
    #expect(controller.providerLocation?.postal == "10004")
    #expect(controller.location?.postal == nil)
    #expect(controller.locationComparison.contains("地区、城市不一致"))
    #expect(await f.transport.calls.isEmpty)
    await runner.failProbe()
    await controller.detectCurrentIP()
    #expect(controller.providerLocation == nil)
    #expect(controller.location == nil)
}
