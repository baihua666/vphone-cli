import Foundation
import Testing
import Yams
@testable import VPhoneWSCore

@Test func ispCityParametersPreserveTransitAndUseFullPortRange() throws {
    let template: [String: Any] = ["server": "isp.decodo.com", "type": "http", "tls": true,
        "username": "user-account-country-us", "password": "fixture", "dialer-proxy": "Transit"]
    let node = try DecodoISP.endpoint(name: "IP · ISP test", template: template, city: "New York", port: 42000)
    #expect(node.configuration["username"] as? String == "user-account-country-us-city-new_york_city")
    #expect(node.configuration["dialer-proxy"] as? String == "Transit")
    #expect(try DecodoISP.nextPort(occupied: [63000, 10001], startingAt: 63000) == 10002)
    #expect(try DecodoISP.nextPort(occupied: [10001, 10002, 10003, 10004], startingAt: 42000) == 42000)
    #expect(throws: (any Error).self) { try DecodoISP.city("new_york-state-california") }
}

@Test func ispCityCreatesDedicatedNodeThenRotatesOnlyItsPort() async throws {
    let fixture = try ClashFixture(); defer { fixture.cleanup() }
    let initial = try await fixture.service.route(context: fixture.context)
    let node = try VMManualProxy(name: "Purchased ISP", host: "isp.decodo.com", port: 10001,
        kind: .http, username: "user-account-country-us", password: "fixture", tls: true)
    try await fixture.service.addProxy(context: fixture.context, proxy: node, expected: initial)
    let before = try await fixture.service.route(context: fixture.context)
    try await fixture.service.configureISP(context: fixture.context, city: "New York", expected: before)
    let first = try await fixture.service.route(context: fixture.context)
    #expect(first.selected == DecodoISP.name(for: fixture.context))
    #expect(first.endpoint != "isp.decodo.com:10001")
    #expect(try await fixture.service.ispCity(context: fixture.context) == "new_york_city")
    try await fixture.service.configureISP(context: fixture.context, city: "New York", expected: first)
    let second = try await fixture.service.route(context: fixture.context)
    #expect(first.selected == second.selected)
    #expect(first.endpoint != second.endpoint)
    let deletes = await fixture.transport.calls.filter { $0.hasPrefix("DELETE") }
    #expect(deletes.allSatisfy { $0 == "DELETE /connections/00000000-0000-0000-0000-000000000001" })
}
