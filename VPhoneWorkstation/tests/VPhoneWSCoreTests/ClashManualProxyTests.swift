import Foundation
import Testing
import Yams
@testable import VPhoneWSCore

@Test func manualProxyPreservesCredentialsAndRejectsMalformedEndpoint() throws {
    let proxy = try VMManualProxy(name: "测试", host: "gateway.example.com", port: 8001,
        kind: .socks5, username: "customer-session-a", password: "# 中文: ' / \\", tls: false, udp: true)
    let yaml = try ClashProxyDocument(text: "prepend: []\nappend: []\ndelete: []\n").adding(proxy, key: "prepend")
    let object = try Yams.load(yaml: yaml) as! [String: Any]
    let nodes = object["prepend"] as! [[String: Any]]
    #expect(nodes[0]["name"] as? String == "IP · 测试")
    #expect(nodes[0]["password"] as? String == "# 中文: ' / \\")
    #expect(nodes[0]["udp"] as? Bool == true)
    for host in ["", "http://example.com", "bad host", "host/path", "host\nname", "example.com:80"] {
        #expect(throws: (any Error).self) { try VMManualProxy(name: "x", host: host, port: 80, kind: .http) }
    }
    #expect(throws: (any Error).self) { try VMManualProxy(name: "bad,node", host: "example.com", port: 80, kind: .http) }
    #expect(throws: (any Error).self) { try VMManualProxy(name: "x", host: "example.com", port: 0, kind: .http) }
    #expect(throws: (any Error).self) { try VMManualProxy(name: "x", host: "example.com", port: 65536, kind: .http) }
    #expect(throws: (any Error).self) { try VMManualProxy(name: "x", host: "example.com", port: 80, kind: .http, username: "user") }
    #expect(throws: (any Error).self) { try VMManualProxy(name: "x", host: "example.com", port: 80, kind: .http, udp: true) }
}

@Test func manualProxyRejectsDuplicateFieldsAliasesAndInvalidSequences() throws {
    let proxy = try VMManualProxy(name: "one", host: "2001:db8::1", port: 1080, kind: .socks5)
    for text in ["prepend: []\nprepend: []\n", "prepend: wrong\n", "prepend: [wrong]\n",
                 "other: &x []\nprepend: *x\n", "prepend: [{name: 'IP · one'}]\n"] {
        #expect(throws: (any Error).self) { try ClashProxyDocument(text: text).adding(proxy, key: "prepend") }
    }
}

@Test func manualProxyInsertionKeepsExistingConfigurationBytes() throws {
    let proxy = try VMManualProxy(name: "one", host: "192.0.2.1", port: 1080, kind: .socks5)
    for text in ["# 🇯🇵\nprepend: [] # keep\nappend: []\ndelete: []\n",
                 "# 🇯🇵\nprepend:\n  - {name: old, type: http} # old comment\nappend: []\ndelete: []\n",
                 "# 🇯🇵\nprepend: [{name: old, type: http}] # keep\nappend: []\ndelete: []\n"] {
        let changed = try ClashProxyDocument(text: text).adding(proxy, key: "prepend")
        #expect(changed.hasPrefix("# 🇯🇵\nprepend:"))
        #expect(changed.contains(text.contains("old comment") ? "# old comment" : "# keep"))
        #expect(changed.hasSuffix("append: []\ndelete: []\n"))
        let root = try Yams.load(yaml: changed) as! [String: Any]
        #expect((root["prepend"] as! [[String: Any]]).first?["name"] as? String == "IP · one")
    }
}

@Test func manualProxyPersistsWithoutSwitchingVMAndSurvivesRecomposition() async throws {
    let fixture = try ClashFixture(); defer { fixture.cleanup() }
    let route = try await fixture.service.route(context: fixture.context)
    let sourceBefore = try Data(contentsOf: fixture.source)
    let proxy = try VMManualProxy(name: "supplier-A", host: "gateway.example.com", port: 8001, kind: .http,
                                  username: "u", password: "p", tls: true)
    try await fixture.service.addProxy(context: fixture.context, proxy: proxy, expected: route)
    let reopened = ClashProxyService(directory: fixture.root, transport: fixture.transport)
    let added = try await reopened.route(context: fixture.context)
    #expect(added.selected == "JP")
    #expect(added.choices.contains("IP · supplier-A"))
    #expect(try Data(contentsOf: fixture.source) == sourceBefore)
    let source = fixture.root.appendingPathComponent("profiles/p.yaml")
    let document = try Yams.load(yaml: String(contentsOf: source, encoding: .utf8)) as! [String: Any]
    let persisted = document["prepend"] as! [[String: Any]]
    #expect(persisted[0]["server"] as? String == "gateway.example.com")
    #expect(persisted[0]["tls"] as? Bool == true)
    #expect(try FileManager.default.attributesOfItem(atPath: source.path)[.posixPermissions] as? Int == 0o600)
    // Verge's proxy enhancement prepends these nodes when regenerating the subscription.
    let runtime = try Yams.load(yaml: String(contentsOf: fixture.runtime, encoding: .utf8)) as! [String: Any]
    #expect(NSDictionary(dictionary: persisted[0]) == NSDictionary(dictionary: (runtime["proxies"] as! [[String: Any]])[0]))
    try await reopened.apply(context: fixture.context, target: proxy.name, expected: added)
    #expect(try await reopened.route(context: fixture.context).selected == proxy.name)
}

@Test func manualProxyDuplicateAndReloadFailureLeaveFilesIntact() async throws {
    let fixture = try ClashFixture(); defer { fixture.cleanup() }
    let route = try await fixture.service.route(context: fixture.context)
    let source = fixture.root.appendingPathComponent("profiles/p.yaml")
    let original = try Data(contentsOf: source), runtime = try Data(contentsOf: fixture.runtime)
    let proxy = try VMManualProxy(name: "new", host: "192.0.2.2", port: 1080, kind: .socks5)
    await fixture.transport.failNextReload()
    await #expect(throws: (any Error).self) { try await fixture.service.addProxy(context: fixture.context, proxy: proxy, expected: route) }
    #expect(try Data(contentsOf: source) == original)
    #expect(try Data(contentsOf: fixture.runtime) == runtime)
    try await fixture.service.addProxy(context: fixture.context, proxy: proxy, expected: route)
    let saved = try Data(contentsOf: source)
    await #expect(throws: (any Error).self) { try await fixture.service.addProxy(context: fixture.context, proxy: proxy, expected: route) }
    #expect(try Data(contentsOf: source) == saved)
}

@Test func manualProxyRollbackDoesNotOverwriteExternalEdits() async throws {
    let fixture = try ClashFixture(); defer { fixture.cleanup() }
    let route = try await fixture.service.route(context: fixture.context)
    let source = fixture.root.appendingPathComponent("profiles/p.yaml")
    let proxy = try VMManualProxy(name: "new", host: "192.0.2.2", port: 1080, kind: .socks5)
    await fixture.transport.failNextReload(edit: source)
    await #expect(throws: (any Error).self) { try await fixture.service.addProxy(context: fixture.context, proxy: proxy, expected: route) }
    #expect(try String(contentsOf: source, encoding: .utf8) == "# external edit\n")
}

@Test func manualProxyCachesExistingSelectionsAndRejectsDisabledPersistence() async throws {
    let fixture = try ClashFixture(); defer { fixture.cleanup() }
    await fixture.transport.addSelector("选择/组 ?")
    let route = try await fixture.service.route(context: fixture.context)
    let proxy = try VMManualProxy(name: "new", host: "192.0.2.2", port: 1080, kind: .socks5)
    let original = try String(contentsOf: fixture.runtime, encoding: .utf8)
    try (original + "profile: {store-selected: false}\n").write(to: fixture.runtime, atomically: true, encoding: .utf8)
    await #expect(throws: (any Error).self) { try await fixture.service.addProxy(context: fixture.context, proxy: proxy, expected: route) }
    #expect(await fixture.transport.calls.filter { $0.hasPrefix("PUT") }.isEmpty)
    try original.write(to: fixture.runtime, atomically: true, encoding: .utf8)
    try await fixture.service.addProxy(context: fixture.context, proxy: proxy, expected: route)
    let calls = await fixture.transport.calls
    let encoded = "选择/组 ?".addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    #expect(calls.contains("PUT /proxies/" + encoded))
    let save = try #require(calls.firstIndex(of: "PUT /proxies/GLOBAL"))
    let reload = try #require(calls.firstIndex(of: "PUT /configs?force=false"))
    #expect(save < reload)
    #expect(await fixture.transport.selection("选择/组 ?") == "US")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["VPHONE_TEST_MIHOMO"] != nil))
func manualProxyConfigurationPassesRealMihomoValidation() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var yaml = "mixed-port: 0\nmode: rule\nproxies: []\nrules: ['MATCH,DIRECT']\n"
    // Use five endpoints, exercising both protocols, TLS, UDP and non-ASCII credential encoding.
    for index in 1...5 {
        let proxy = try VMManualProxy(name: "测试 \(index)", host: "gateway.example.com", port: 8000 + index,
            kind: index.isMultiple(of: 2) ? .http : .socks5, username: "session-\(index)",
            password: "test: # / 中文", tls: index == 2, udp: index == 1)
        yaml = try ClashProxyDocument(text: yaml).adding(proxy, key: "proxies")
    }
    let context = try VMCommandContext(name: "test", executable: root.appendingPathComponent("vphone-cli"), libraryRoot: root.path)
    let original = try DecodoProxy(context: context, username: "test", password: "test: # / 中文", zip: "02108")
    let rotated = try DecodoProxy(context: context, username: "test", password: "test: # / 中文", zip: "10001")
    yaml = try ClashProxyDocument(text: yaml).adding(original.proxy, key: "proxies")
    yaml = try ClashProxyDocument(text: yaml).replacing(rotated.proxy, key: "proxies", expected: original.proxy.configuration)
    let config = root.appendingPathComponent("config.yaml")
    try yaml.write(to: config, atomically: true, encoding: .utf8)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VPHONE_TEST_MIHOMO"]!)
    process.arguments = ["-t", "-d", root.path, "-f", config.path]
    process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
    try process.run(); process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}

@Test func manualProxyAdditionRejectsAutomaticGroups() async throws {
    let fixture = try ClashFixture(); defer { fixture.cleanup() }
    let route = try await fixture.service.route(context: fixture.context)
    let proxy = try VMManualProxy(name: "supplier US", host: "gate.decodo.com", port: 7000, kind: .http)
    let original = try String(contentsOf: fixture.runtime, encoding: .utf8)
    let automatic = original + "proxy-groups:\n- {name: automatic, type: url-test, include-all: true}\n"
    try automatic.write(to: fixture.runtime, atomically: true, encoding: .utf8)
    await #expect(throws: (any Error).self) { try await fixture.service.addProxy(context: fixture.context, proxy: proxy, expected: route) }
    #expect(try String(contentsOf: fixture.runtime, encoding: .utf8) == automatic)
}

@Test func manualProxyAllowsSupplierLabelWithoutReservingAllDecodoNames() async throws {
    let fixture = try ClashFixture(); defer { fixture.cleanup() }
    let route = try await fixture.service.route(context: fixture.context)
    let proxy = try VMManualProxy(name: "Decodo US", host: "gate.decodo.com", port: 7000, kind: .http)
    try await fixture.service.addProxy(context: fixture.context, proxy: proxy, expected: route)
    #expect(try await fixture.service.route(context: fixture.context).choices.contains(proxy.name))
}
