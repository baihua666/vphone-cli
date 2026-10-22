import Foundation
import Testing
import Yams
@testable import VPhoneWSCore

@Test func decodoValidatesZIPAndBuildsIndependentFiveMinuteSessions() throws {
    let fixture = try ClashFixture(); defer { fixture.cleanup() }
    let first = try DecodoProxy(context: fixture.context, username: "user-test_user", password: "secret", zip: "02108")
    let second = try DecodoProxy(context: fixture.context, username: "test_user", password: "secret", zip: "10001")
    #expect(first.proxy.name == second.proxy.name)
    #expect(first.session.id != second.session.id)
    #expect(first.proxy.configuration["username"] as? String == "user-test_user-country-us-zip-02108-session_iplock-\(first.session.id)-sessionduration-5")
    #expect(first.proxy.configuration["tls"] as? Bool == true)
    for zip in ["", "1234", "123456", "１２３４５", "10001-country-ca", "10001-1234"] {
        #expect(throws: (any Error).self) { try DecodoProxy(context: fixture.context, username: "u", password: "p", zip: zip) }
    }
    #expect(throws: (any Error).self) { try DecodoProxy(context: fixture.context, username: "u-country-ca", password: "p", zip: "10001") }
    #expect(throws: (any Error).self) { try DecodoProxy(context: fixture.context, username: "u", password: "", zip: "10001") }
}

@Test func decodoConfigureRotateAndReopenKeepsSingleNodeAndOtherVMUntouched() async throws {
    let fixture = try ClashFixture(); defer { fixture.cleanup() }
    var route = try await fixture.service.route(context: fixture.context)
    let first = try await fixture.service.configureDecodo(context: fixture.context, username: "user-u", password: "secret", zip: "02108", expected: route)
    route = try await fixture.service.route(context: fixture.context)
    let nodeName = route.selected
    let source = fixture.root.appendingPathComponent("profiles/p.yaml")
    let before = try String(contentsOf: source, encoding: .utf8)
    #expect(before.contains("# preserve proxy comments"))
    let next = try await fixture.service.rotateDecodo(context: fixture.context, zip: "10001", expected: route)
    #expect(first.id != next.id)
    #expect(next.zip == "10001")
    let reopened = ClashProxyService(directory: fixture.root, transport: fixture.transport)
    #expect(try await reopened.decodoSession(context: fixture.context) == next)
    #expect(try await reopened.route(context: fixture.context).selected == nodeName)
    let saved = try Yams.load(yaml: String(contentsOf: source, encoding: .utf8)) as! [String: Any]
    #expect((saved["prepend"] as! [[String: Any]]).count == 1)
    #expect(try String(contentsOf: fixture.source, encoding: .utf8).contains("PROCESS-PATH,/other/vphone-vm,US"))
    let deletes = await fixture.transport.calls.filter { $0.hasPrefix("DELETE") }
    #expect(deletes.count == 2)
    #expect(deletes.allSatisfy { $0.hasSuffix("00000000-0000-0000-0000-000000000001") })
}

@Test func decodoReloadFailureRestoresCredentialsSessionAndRules() async throws {
    let fixture = try ClashFixture(); defer { fixture.cleanup() }
    var route = try await fixture.service.route(context: fixture.context)
    _ = try await fixture.service.configureDecodo(context: fixture.context, username: "u", password: "old", zip: "10001", expected: route)
    route = try await fixture.service.route(context: fixture.context)
    let urls = [fixture.source, fixture.runtime, fixture.root.appendingPathComponent("profiles/p.yaml")]
    let before = try urls.map { try Data(contentsOf: $0) }
    await fixture.transport.failNextReload()
    await #expect(throws: (any Error).self) {
        try await fixture.service.configureDecodo(context: fixture.context, username: "other", password: "new", zip: "90210", expected: route)
    }
    #expect(try urls.map { try Data(contentsOf: $0) } == before)
}

@Test func proxyCredentialReplacementPreservesBlockAndFlowDocuments() throws {
    let old = try VMManualProxy(name: "managed", host: "gate.decodo.com", port: 7000, kind: .http, username: "old", password: "old", tls: true)
    let new = try VMManualProxy(name: "managed", host: "gate.decodo.com", port: 7000, kind: .http, username: "new", password: "# ' 中文 , }", tls: true)
    let flow = try ClashProxyDocument(text: "# keep\nproxies: []\nrules: []\n").adding(old, key: "proxies")
    let block = "# keep\nproxies:\n- name: 'IP · managed'\n  type: http\n  server: gate.decodo.com\n  port: 7000\n  tls: true\n  username: old # comment\n  password: old\nrules: []\n"
    let plainFlow = "# keep\nproxies: [{name: IP · managed, type: http, server: gate.decodo.com, port: 7000, tls: true, username: old, password: old}]\nrules: []\n"
    for text in [flow, block, plainFlow] {
        let changed = try ClashProxyDocument(text: text).replacing(new, key: "proxies", expected: old.configuration)
        #expect(changed.hasPrefix("# keep\n"))
        #expect(changed.hasSuffix("rules: []\n"))
        let node = try ClashProxyDocument(text: changed).configuration(named: old.name, key: "proxies")!
        #expect(NSDictionary(dictionary: node) == NSDictionary(dictionary: new.configuration))
        if text == block { #expect(changed.contains("# comment")) }
    }
}

@Test func fiveDecodoVMsHaveIndependentNodesSessionsAndRouting() async throws {
    let fixture = try ClashFixture(); defer { fixture.cleanup() }
    var contexts = [fixture.context]
    var source = try String(contentsOf: fixture.source, encoding: .utf8)
    var runtime = try String(contentsOf: fixture.runtime, encoding: .utf8)
    for index in 1...4 {
        let name = "vm\(index)"
        let context = try VMCommandContext(name: name, executable: fixture.root.appendingPathComponent("runtime\(index)/vphone-cli"),
            libraryRoot: fixture.root.appendingPathComponent("machines").path)
        try FileManager.default.createDirectory(at: context.directory, withIntermediateDirectories: true)
        contexts.append(context)
        let process = context.executable.deletingLastPathComponent().appendingPathComponent("vphone-vm").path
        source = source.replacingOccurrences(of: "append: []", with: "- PROCESS-PATH,\(process),JP\nappend: []")
        runtime += "- PROCESS-PATH,\(process),JP\n"
    }
    for context in contexts {
        try JSONSerialization.data(withJSONObject: ["executablePath": context.executable.path])
            .write(to: context.directory.appendingPathComponent(".vphone-ws.json"))
    }
    try source.write(to: fixture.source, atomically: true, encoding: .utf8)
    try runtime.write(to: fixture.runtime, atomically: true, encoding: .utf8)
    _ = try await fixture.transport.request(socket: "", secret: "", method: "PUT", path: "/configs?force=false",
        body: JSONSerialization.data(withJSONObject: ["payload": runtime]))
    var sessions: [DecodoSession] = []
    for context in contexts {
        let route = try await fixture.service.route(context: context)
        sessions.append(try await fixture.service.configureDecodo(context: context, username: "u", password: "p", zip: "10001", expected: route))
    }
    #expect(Set(sessions.map(\.id)).count == 5)
    #expect(Set(contexts.map { DecodoProxy.name(for: $0) }).count == 5)
    let nodeNames = Set(contexts.map { DecodoProxy.name(for: $0) })
    for context in contexts {
        let route = try await fixture.service.route(context: context)
        #expect(route.selected == DecodoProxy.name(for: context))
        #expect(Set(route.choices).intersection(nodeNames) == [route.selected])
    }
    var firstRoute = try await fixture.service.route(context: contexts[0])
    await #expect(throws: (any Error).self) {
        try await fixture.service.apply(context: contexts[0], target: DecodoProxy.name(for: contexts[1]), expected: firstRoute)
    }
    for _ in 1...3 {
        _ = try await fixture.service.rotateDecodo(context: contexts[0], zip: "02108", expected: firstRoute)
        firstRoute = try await fixture.service.route(context: contexts[0])
    }
    for index in 1...4 {
        #expect(try await fixture.service.decodoSession(context: contexts[index]) == sessions[index])
        #expect(try await fixture.service.route(context: contexts[index]).selected == DecodoProxy.name(for: contexts[index]))
    }
    let saved = try Yams.load(yaml: String(contentsOf: fixture.root.appendingPathComponent("profiles/p.yaml"), encoding: .utf8)) as! [String: Any]
    #expect((saved["prepend"] as! [[String: Any]]).count == 5)
}

@Test func decodoRejectsSharedNodeAndPreservesConcurrentExternalEdits() async throws {
    let fixture = try ClashFixture(); defer { fixture.cleanup() }
    var route = try await fixture.service.route(context: fixture.context)
    _ = try await fixture.service.configureDecodo(context: fixture.context, username: "u", password: "p", zip: "10001", expected: route)
    route = try await fixture.service.route(context: fixture.context)
    let before = try Data(contentsOf: fixture.runtime)
    await fixture.transport.selectManagedNode(route.selected)
    await #expect(throws: (any Error).self) { try await fixture.service.rotateDecodo(context: fixture.context, zip: "02108", expected: route) }
    #expect(try Data(contentsOf: fixture.runtime) == before)
    await fixture.transport.selectManagedNode("US")
    await fixture.transport.failNextReload(edit: fixture.source)
    await #expect(throws: (any Error).self) { try await fixture.service.rotateDecodo(context: fixture.context, zip: "02108", expected: route) }
    #expect(try String(contentsOf: fixture.source, encoding: .utf8) == "# external edit\n")
    #expect(try Data(contentsOf: fixture.runtime) == before)
}

extension MockMihomo {
    func selectManagedNode(_ name: String) { nodes["GLOBAL"] = ["type": "Selector", "all": ["US", name], "now": name] }
}

@Test func decodoRejectsAutomaticGroupMembershipBeforeWriting() async throws {
    for option in ["include-all", "include-all-proxies"] {
        let fixture = try ClashFixture(); defer { fixture.cleanup() }
        let original = try String(contentsOf: fixture.runtime, encoding: .utf8)
        let changed = original + "proxy-groups:\n- {name: automatic, type: load-balance, \(option): true}\n"
        try changed.write(to: fixture.runtime, atomically: true, encoding: .utf8)
        let route = try await fixture.service.route(context: fixture.context)
        await #expect(throws: (any Error).self) {
            try await fixture.service.configureDecodo(context: fixture.context, username: "u", password: "p", zip: "10001", expected: route)
        }
        #expect(try String(contentsOf: fixture.runtime, encoding: .utf8) == changed)
        #expect(await fixture.transport.calls.allSatisfy { !$0.hasPrefix("PUT") })
    }
}

@Test func decodoRejectsLoadBalancedSharingWithoutCurrentSelection() async throws {
    let fixture = try ClashFixture(); defer { fixture.cleanup() }
    var route = try await fixture.service.route(context: fixture.context)
    _ = try await fixture.service.configureDecodo(context: fixture.context, username: "u", password: "p", zip: "10001", expected: route)
    route = try await fixture.service.route(context: fixture.context)
    await fixture.transport.includeManagedNodeInLoadBalancer(route.selected)
    let before = try Data(contentsOf: fixture.runtime)
    await #expect(throws: (any Error).self) {
        try await fixture.service.rotateDecodo(context: fixture.context, zip: "02108", expected: route)
    }
    #expect(try Data(contentsOf: fixture.runtime) == before)
}

extension MockMihomo {
    func includeManagedNodeInLoadBalancer(_ name: String) { nodes["balanced"] = ["type": "LoadBalance", "all": ["US", name]] }
}

@Test func decodoRotationPreservesExistingGatewayDialerOnly() throws {
    let fixture = try ClashFixture(); defer { fixture.cleanup() }
    let old = try DecodoProxy(context: fixture.context, username: "u", password: "p", zip: "10001")
    let next = try DecodoProxy(context: fixture.context, username: "u", password: "p", zip: "02108")
    var node = old.proxy.configuration
    node["dialer-proxy"] = "existing-transit"
    let source = try Yams.dump(object: ["proxies": [node]])
    let changed = try ClashProxyDocument(text: source).replacing(next.proxy, key: "proxies", expected: node)
    let actual = try ClashProxyDocument(text: changed).configuration(named: old.proxy.name, key: "proxies")!
    #expect(actual["dialer-proxy"] as? String == "existing-transit")
    #expect(try DecodoProxy.decode(actual).session == next.session)
    for extra in ["skip-cert-verify", "unexpected"] {
        var invalid = node; invalid[extra] = true
        let source = try Yams.dump(object: ["proxies": [invalid]])
        #expect(throws: (any Error).self) {
            try ClashProxyDocument(text: source).replacing(next.proxy, key: "proxies", expected: invalid)
        }
    }
}
