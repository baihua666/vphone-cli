import Foundation
import VPhoneWSCore
import VPhoneFlywheel

struct VPhoneLaunchpadMachinePath: Hashable {
    let libraryRoot: String
    let name: String
    var url: URL { URL(fileURLWithPath: libraryRoot).appendingPathComponent(name) }
}
struct VPhoneLaunchpadMachine {
    struct Network { var mode = "tunnel" }
    let path: VPhoneLaunchpadMachinePath
    var name: String { path.name }
    var udid: String? = "same-udid"
    var network = Network()
}
@MainActor final class VPhoneLaunchpadMachineLibrary {
    enum RunState: Equatable { case running, stopped }
    var hasListed = true
    var listError: String?
    var machines: [VPhoneLaunchpadMachine] = []
    var roots: [String] = []
    var runState = RunState.running
    var starts = 0
    var stops = 0
    func state(of path: VPhoneLaunchpadMachinePath) -> RunState { runState }
    func refresh() async {}
    func start(_ path: VPhoneLaunchpadMachinePath) async { starts += 1; runState = .running }
    func stop(_ path: VPhoneLaunchpadMachinePath) async { stops += 1; runState = .stopped }
}
@MainActor enum VPhoneLaunchpadBundleStore {
    static var root = URL(fileURLWithPath: "/unused-test-store")
}
@MainActor enum VPhoneLaunchpadProxyServices {
    static let proxy = ClashProxyService()
}
enum VPhoneLaunchpadError {
    static func message(for error: any Error) -> String { error.localizedDescription }
}
@MainActor enum VPhoneLaunchpadGuestSocket {
    static var requests: [([String: Any], String, Int)] = []
    static var handler: ([String: Any]) throws -> [String: Any] = { _ in [:] }
    static func send(_ object: [String: Any], socketPath: String, timeout: Int) async throws -> Any {
        requests.append((object, socketPath, timeout))
        return try handler(object)
    }
}

@main @MainActor
struct FlywheelWebActionTests {
    static func main() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        VPhoneLaunchpadBundleStore.root = temporary.appendingPathComponent("store")
        let library = VPhoneLaunchpadMachineLibrary()
        let first = VPhoneLaunchpadMachine(path: .init(libraryRoot: temporary.appendingPathComponent("a").path, name: "phone"))
        let second = VPhoneLaunchpadMachine(path: .init(libraryRoot: temporary.appendingPathComponent("b").path, name: "phone"))
        library.machines = [first, second]
        library.roots = [first.path.libraryRoot, second.path.libraryRoot]
        let serialized = VPhoneLaunchpadFlywheelWebAction()
        try await serialized.exclusively(on: first.path) {
            precondition(serialized.active == first.path)
            do {
                try await serialized.exclusively(on: second.path) { preconditionFailure("Overlapping work must be rejected") }
            } catch is VPhoneFlywheelError {}
        }
        precondition(serialized.active == nil)
        do {
            try await serialized.exclusively(on: first.path) { throw VPhoneFlywheelError("failed preparation") }
        } catch is VPhoneFlywheelError {}
        precondition(serialized.active == nil, "A failed preparation must allow independent retry")
        for machine in library.machines {
            try FileManager.default.createDirectory(at: machine.path.url, withIntermediateDirectories: true)
            try Data(#"{"bundle":"2.8.0-test"}"#.utf8).write(to: machine.path.url.appendingPathComponent("launchpad.json"))
        }

        let network = VPhoneLaunchpadFlywheelNetwork.shared
        let firstTime = Date(timeIntervalSince1970: 100)
        network.record("1.2.3.4", for: first.path, at: firstTime)
        network.record("5.6.7.8", for: second.path)
        precondition(network.measurements[first.path]?.checkedAt == firstTime)
        network.invalidate(first.path)
        precondition(network.measurements[first.path] == nil)
        precondition(network.measurements[second.path]?.ip == "5.6.7.8")

// Native detection already has a guest result. A second RPC must never gate its display.
VPhoneLaunchpadGuestSocket.requests = []
VPhoneLaunchpadGuestSocket.handler = { _ in throw VPhoneFlywheelError("second probe unavailable") }
var nativeCalls = 0
await network.performMeasured(on: first.path) {
    nativeCalls += 1
    precondition(network.measurements[first.path] == nil)
    precondition(network.messages[first.path]?.contains("正在检测") == true)
    return ("23.24.25.26", "检测完成，未修改代理。")
}
precondition(nativeCalls == 1)
precondition(VPhoneLaunchpadGuestSocket.requests.isEmpty, "Do not repeat a completed guest probe")
precondition(network.measurements[first.path]?.ip == "23.24.25.26", "Successful native detection must be displayed")
for failure in ["Guest egress check timed out", "实例尚未运行"] {
    await network.performMeasured(on: first.path) { (nil, failure) }
    precondition(network.measurements[first.path] == nil, "Do not show a stale IP after failure")
    precondition(network.messages[first.path] == failure, "Show the failure in the current IP view")
}
network.record("23.24.25.26", for: first.path)
try await VPhoneLaunchpadFlywheelWebAction.shared.exclusively(on: second.path) {
    await network.performMeasured(on: first.path) { preconditionFailure("Must not overlap") }
    precondition(network.measurements[first.path]?.ip == "23.24.25.26")
}
precondition(network.measurements[second.path]?.ip == "5.6.7.8")

        var expectedURL = "https://business.example/?x=1&ip=23.24.25.26"
        func response(_ request: [String: Any]) throws -> [String: Any] {
            let result: [String: Any]
            if request["t"] as? String == "network" {
                result = ["device": true, "link": "up", "attachment": "tunnel",
                          "native_proxy_enabled": true, "native_proxy_endpoint": "isp.decodo.com:10001"]
            } else if request["method"] as? String == "network.egress" {
                result = ["origin": "guest", "ip": "23.24.25.26"]
            } else {
                precondition(request["t"] as? String == "rpc")
                precondition(request["method"] as? String == "apps.open_url")
                let params = request["params"] as! [String: Any]
                precondition(params["bundle_id"] as? String == "com.apple.mobilesafari")
                precondition(params["url"] as? String == expectedURL)
                result = params
            }
            return ["ok": true, "result": result]
        }
        func run(_ machine: VPhoneLaunchpadMachine, expectSuccess: Bool, focusFails: Bool = false, includeIP: Bool = true,
                 parameters: [VPhoneFlywheelURLParameter] = [], customURL: String? = nil) async {
            expectedURL = customURL ?? (includeIP ? "https://business.example/?x=1&ip=23.24.25.26" : "https://business.example/?x=1")
            VPhoneLaunchpadGuestSocket.requests = []
            var focused: [VPhoneLaunchpadMachinePath] = []
            let action = VPhoneLaunchpadFlywheelWebAction { guest in
                precondition(VPhoneLaunchpadGuestSocket.requests.last?.0["method"] as? String == "apps.open_url")
                focused.append(guest.machine.path)
                if focusFails { throw VPhoneFlywheelError("test activation failure") }
            }
            var snapshot = parameters
            action.open(url: "https://business.example/?x=1&ip=old", includeIP: includeIP, parameters: snapshot, machine: machine, library: library)
            if !snapshot.isEmpty { snapshot[0].value = "changed after click; must not be sent" }
            // A duplicate click cannot create a second workflow.
            action.open(url: "https://wrong.example/", machine: second, library: library)
            let deadline = Date().addingTimeInterval(3)
            while action.active != nil {
                precondition(Date() < deadline)
                await Task.yield()
            }
            let message = action.messages[machine.path] ?? ""
            precondition(expectSuccess == message.hasPrefix("Safari 打开请求已完成"), message)
            precondition(action.messages.count == 1)
            precondition(focused == (expectSuccess ? [machine.path] : []))
            precondition(message.contains("窗口切换失败") == focusFails)
            if expectSuccess {
                precondition(message.contains("未附加 ip 参数") == !includeIP)
                precondition(!message.contains("23.24.25.26"), "Status messages must not keep independent IP copies")
                precondition(network.measurements[machine.path]?.ip == "23.24.25.26")
                precondition(network.measurements[machine.path]!.checkedAt > firstTime)
            } else {
                precondition(network.measurements[machine.path] == nil, "Failed operations must clear stale IPs")
            }
            let calls = VPhoneLaunchpadGuestSocket.requests
            precondition(calls.allSatisfy { $0.1 == machine.path.url.appendingPathComponent("vphone.sock").path })
            if expectSuccess {
                precondition(calls.map { $0.0["method"] as? String ?? "network" } == ["network", "network.egress", "network", "apps.open_url"])
                precondition(calls.map { $0.2 } == [10, 30, 10, 30])
            } else {
                precondition(!calls.contains { $0.0["method"] as? String == "apps.open_url" })
            }
        }

        VPhoneLaunchpadGuestSocket.handler = response
        await run(first, expectSuccess: true)
        await run(second, expectSuccess: true) // Same name and UDID, different library/socket.
        await run(first, expectSuccess: true, focusFails: true) // Safari success survives activation failure.
        await run(first, expectSuccess: true, includeIP: false) // Unchecked IP still opens/focuses this VM.
        await run(second, expectSuccess: true) // Re-enabling uses the freshly measured IP.
        let custom: [VPhoneFlywheelURLParameter] = [
            .init(name: "x", value: "中文 + &"), .init(isEnabled: false, name: "hidden", value: "not sent"),
        ]
        await run(first, expectSuccess: true, parameters: custom,
            customURL: "https://business.example/?ip=23.24.25.26&x=%E4%B8%AD%E6%96%87%20%2B%20%26")
        await run(second, expectSuccess: true, includeIP: false, parameters: custom,
            customURL: "https://business.example/?x=%E4%B8%AD%E6%96%87%20%2B%20%26")
        for (network, expected) in [
            (["device": true, "link": "up", "attachment": "nat"] as [String: Any], "nat"),
            (["device": true, "link": "down", "attachment": "tunnel"], "链路已断开"),
            (["device": false], "没有网络设备"),
            (["device": true, "link": "up", "attachment": "tunnel", "native_proxy_enabled": true,
              "native_proxy_endpoint": "other.example:443"], "DECODO"),
        ] {
            VPhoneLaunchpadGuestSocket.handler = { _ in ["ok": true, "result": network] }
            let guest = try VPhoneLaunchpadFlywheelGuest(machine: first, library: library)
            do {
                _ = try await guest.route()
                preconditionFailure("Expected an actionable readiness failure")
            } catch { precondition(error.localizedDescription.contains(expected), error.localizedDescription) }
        }
        VPhoneLaunchpadGuestSocket.handler = response
        let measurement = try VPhoneLaunchpadFlywheelGuest(machine: first, library: library)
        VPhoneLaunchpadGuestSocket.requests = []
        let measuredIP = try await measurement.measure()
        precondition(measuredIP == "23.24.25.26")
        precondition(!VPhoneLaunchpadGuestSocket.requests.contains { $0.0["method"] as? String == "apps.open_url" })
        let executable = VPhoneLaunchpadBundleStore.root.appendingPathComponent("2.8.0-test/VPhone.bundle/Contents/MacOS/vphone-cli")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fixture = """
        #!/bin/sh
        case "$*" in
          *--help*) echo tunnel ;;
          *) echo '{"device":true,"link":"up","attachment":"tunnel","guest_addresses":["en0 192.168.127.3"]}' ;;
        esac
        """
        try Data(fixture.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        var stale = first
        stale.network.mode = "nat"
        let preparedIP = try await VPhoneLaunchpadFlywheelNetwork().prepare(stale, library: library)
        precondition(preparedIP == measuredIP)
        precondition(library.starts == 0 && library.stops == 0, "Retry must use refreshed tunnel mode, not the original NAT form snapshot")
        await network.check(first, library: library)
        precondition(network.measurements[first.path]?.ip == measuredIP)
        precondition(!(network.messages[first.path] ?? "").contains(measuredIP))
        library.runState = .stopped
        await run(first, expectSuccess: false)
        precondition(VPhoneLaunchpadGuestSocket.requests.isEmpty)
        library.runState = .running
        library.listError = "refresh failed"
        await run(first, expectSuccess: false)
        library.listError = nil

        VPhoneLaunchpadGuestSocket.handler = { request in
            if request["t"] as? String == "network" { return ["ok": false, "error": "unsupported"] }
            return try response(request)
        }
        await run(first, expectSuccess: false)

        VPhoneLaunchpadGuestSocket.handler = { request in
            if request["method"] as? String == "network.egress" {
                try Data(#"{"bundle":"2.8.1-test"}"#.utf8).write(to: first.path.url.appendingPathComponent("launchpad.json"))
            }
            return try response(request)
        }
        await run(first, expectSuccess: false)
        VPhoneLaunchpadGuestSocket.handler = response
        await run(first, expectSuccess: true) // Retry resolves the new pinned binding.

        VPhoneLaunchpadGuestSocket.handler = { request in
            if request["method"] as? String == "network.egress" {
                // Retain the source so inode reuse cannot mask a same-name replacement.
                try FileManager.default.moveItem(at: first.path.url, to: temporary.appendingPathComponent("old-phone"))
                try FileManager.default.createDirectory(at: first.path.url, withIntermediateDirectories: true)
            }
            return try response(request)
        }
        await run(first, expectSuccess: false)
        print("FLYWHEEL adapter: RPC/Safari contracts, success-only window focus, activation failure, instance isolation, duplicate click, stopped/stale list, capability failure, pinned binding, retry and directory replacement passed.")
    }
}
