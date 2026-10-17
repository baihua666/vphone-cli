import Foundation
import Testing
import Yams
@testable import VPhoneWSCore

@Test func clashScalarReplacementPreservesOtherBytes() throws {
    for scalar in ["PROCESS-PATH,/vm/a,日本", "\"PROCESS-PATH,/vm/a,\\U0001F1EF\\U0001F1F5\n  日本\"", "'PROCESS-PATH,/vm/a,日本'", "\"PROCESS-PATH,/vm/a,日本\""] {
        let text = "# 注释 🇯🇵\nprepend:\n- \(scalar) # keep\n- PROCESS-PATH,/vm/b,美国\nappend: []\ndelete: []\n"
        let changed = try ClashRuleDocument(text: text, key: "prepend", process: "/vm/a").replacing(target: "🇺🇸 美国 BGP")
        #expect(changed.hasPrefix("# 注释 🇯🇵\nprepend:\n- \""))
        #expect(!changed.contains(#"\/"#))
        #expect(changed.hasSuffix(" # keep\n- PROCESS-PATH,/vm/b,美国\nappend: []\ndelete: []\n"))
        #expect(try ClashRuleDocument(text: changed, key: "prepend", process: "/vm/a").target() == "🇺🇸 美国 BGP")
    }
}

@Test func clashRefusesAmbiguousRulesAndInvalidTargets() throws {
    for text in ["prepend: []", "prepend:\n- PROCESS-PATH,/vm/a,JP\n- PROCESS-PATH,/vm/a,US", "prepend:\n- PROCESS-PATH,/vm/a,JP,no-resolve"] {
        #expect(throws: (any Error).self) { try ClashRuleDocument(text: text, key: "prepend", process: "/vm/a").target() }
    }
    let rule = ClashRuleDocument(text: "prepend:\n- PROCESS-PATH,/vm/a,JP", key: "prepend", process: "/vm/a")
    #expect(throws: (any Error).self) { try rule.replacing(target: "bad,node") }
}

private actor MockMihomo: MihomoTransport {
    var rules: [[String: String]]
    var calls: [String] = []
    var failReload = false
    var externalEdit: URL?
    init(process: String) {
        rules = [["type": "Domain", "payload": "example.org", "proxy": "DIRECT"],
                 ["type": "ProcessPath", "payload": process, "proxy": "JP"],
                 ["type": "ProcessPath", "payload": "/other/vphone-vm", "proxy": "US"]]
    }
    func failNextReload(edit: URL? = nil) { failReload = true; externalEdit = edit }
    func request(socket: String, secret: String, method: String, path: String, body: Data?) async throws -> Data {
        calls.append(method + " " + path)
        switch path {
        case "/configs": return Data(#"{"mode":"rule","tun":{"enable":true},"find-process-mode":"strict"}"#.utf8)
        case "/rules": return try JSONSerialization.data(withJSONObject: ["rules": rules])
        case "/proxies": return Data(#"{"proxies":{"JP":{"type":"Shadowsocks"},"US":{"type":"Shadowsocks"},"GLOBAL":{"type":"Selector","all":["JP","US"]}}}"#.utf8)
        case "/configs?force=false":
            if failReload {
                failReload = false
                if let externalEdit { try "# external edit\n".write(to: externalEdit, atomically: true, encoding: .utf8) }
                throw ProxyRouteError("reload failed")
            }
            let json = try JSONSerialization.jsonObject(with: body!) as! [String: String]
            let config = try Yams.load(yaml: json["payload"]!) as! [String: Any]
            rules = (config["rules"] as! [String]).map {
                let fields = $0.components(separatedBy: ",")
                return ["type": fields[0] == "PROCESS-PATH" ? "ProcessPath" : "Domain", "payload": fields[1], "proxy": fields[2]]
            }
            return Data()
        case "/connections":
            return try JSONSerialization.data(withJSONObject: ["connections": [
                ["id": "00000000-0000-0000-0000-000000000001", "metadata": ["processPath": rules[1]["payload"]!]],
                ["id": "00000000-0000-0000-0000-000000000002", "metadata": ["processPath": "/other/vphone-vm"]]
            ]])
        default: return Data()
        }
    }
}

private struct ClashFixture {
    let root: URL
    let source: URL
    let runtime: URL
    let context: VMCommandContext
    let transport: MockMihomo
    let service: ClashProxyService
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("profiles"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("machines/a"), withIntermediateDirectories: true)
        let exe = root.appendingPathComponent("runtime/vphone-cli")
        context = try VMCommandContext(name: "a", executable: exe, libraryRoot: root.appendingPathComponent("machines").path)
        let process = exe.deletingLastPathComponent().appendingPathComponent("vphone-vm").path
        source = root.appendingPathComponent("profiles/r.yaml")
        runtime = root.appendingPathComponent("clash-verge.yaml")
        try "current: active\nitems:\n- uid: active\n  option: {rules: r}\n- uid: r\n  type: rules\n  file: r.yaml\n".write(to: root.appendingPathComponent("profiles.yaml"), atomically: true, encoding: .utf8)
        try "prepend:\n- PROCESS-PATH,\(process),JP\n- PROCESS-PATH,/other/vphone-vm,US\nappend: []\ndelete: []\n".write(to: source, atomically: true, encoding: .utf8)
        try "external-controller-unix: /tmp/test.sock\nsecret: test-only\nrules:\n- DOMAIN,example.org,DIRECT\n- PROCESS-PATH,\(process),JP\n- PROCESS-PATH,/other/vphone-vm,US\n".write(to: runtime, atomically: true, encoding: .utf8)
        transport = MockMihomo(process: process)
        service = ClashProxyService(directory: root, transport: transport)
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

@Test func clashSwitchPersistsOnlyTargetAndDisconnectsOnlyItsFlows() async throws {
    let fixture = try ClashFixture(); defer { fixture.cleanup() }
    let route = try await fixture.service.route(context: fixture.context)
    #expect(route.choices == ["JP", "US"])
    try await fixture.service.apply(context: fixture.context, target: "US", expected: route)
    let saved = try String(contentsOf: fixture.source, encoding: .utf8)
    #expect(saved.contains("/other/vphone-vm,US\nappend: []\ndelete: []"))
    let reopened = ClashProxyService(directory: fixture.root, transport: fixture.transport)
    #expect(try await reopened.route(context: fixture.context).selected == "US")
    let deletes = await fixture.transport.calls.filter { $0.hasPrefix("DELETE") }
    #expect(deletes == ["DELETE /connections/00000000-0000-0000-0000-000000000001"])
    await #expect(throws: (any Error).self) { try await reopened.apply(context: fixture.context, target: "JP", expected: route) }
}

@Test func clashReloadFailureRestoresOriginalFiles() async throws {
    let fixture = try ClashFixture(); defer { fixture.cleanup() }
    let source = try Data(contentsOf: fixture.source), runtime = try Data(contentsOf: fixture.runtime)
    let route = try await fixture.service.route(context: fixture.context)
    await fixture.transport.failNextReload()
    await #expect(throws: (any Error).self) { try await fixture.service.apply(context: fixture.context, target: "US", expected: route) }
    #expect(try Data(contentsOf: fixture.source) == source)
    #expect(try Data(contentsOf: fixture.runtime) == runtime)
    #expect(try await fixture.service.route(context: fixture.context).selected == "JP")
}

@Test func clashRollbackDoesNotOverwriteExternalEdits() async throws {
    let fixture = try ClashFixture(); defer { fixture.cleanup() }
    let route = try await fixture.service.route(context: fixture.context)
    await fixture.transport.failNextReload(edit: fixture.source)
    await #expect(throws: (any Error).self) { try await fixture.service.apply(context: fixture.context, target: "US", expected: route) }
    #expect(try String(contentsOf: fixture.source, encoding: .utf8) == "# external edit\n")
}

@Test func clashRejectsSharedRuntimeAndMissingNode() async throws {
    let fixture = try ClashFixture(); defer { fixture.cleanup() }
    let route = try await fixture.service.route(context: fixture.context)
    await #expect(throws: (any Error).self) { try await fixture.service.apply(context: fixture.context, target: "gone", expected: route) }
    let other = fixture.root.appendingPathComponent("machines/b")
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: ["executablePath": fixture.context.executable.path])
        .write(to: other.appendingPathComponent(".vphone-ws.json"))
    await #expect(throws: (any Error).self) { _ = try await fixture.service.route(context: fixture.context) }
    try FileManager.default.removeItem(at: other.appendingPathComponent(".vphone-ws.json"))
    try Data().write(to: other.appendingPathComponent("config.plist"))
    await #expect(throws: (any Error).self) { _ = try await fixture.service.route(context: fixture.context) }
}
