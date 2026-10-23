import AppKit
import Foundation
import VPhoneFlywheel
import VPhoneWSCore

/// One pinned context for business checks, preparation and guest requests.
@MainActor
struct VPhoneLaunchpadFlywheelGuest {
    let machine: VPhoneLaunchpadMachine
    let library: VPhoneLaunchpadMachineLibrary
    let client: VPhoneCLIClient
    let context: VMCommandContext
    let identity: String

    init(machine: VPhoneLaunchpadMachine, library: VPhoneLaunchpadMachineLibrary) throws {
        self.machine = machine
        self.library = library
        let store = VPhoneLaunchpadBundleStore.root
        client = VPhoneCLIClient(executable: store, libraryRoot: machine.path.libraryRoot,
            runner: SystemCLIRunner(), launchpadStore: store, isolationRoots: library.roots)
        context = try client.context(name: machine.name)
        guard let identity = VPhoneFlywheelMachineReference.directoryIdentity(at: context.directory) else {
            throw VPhoneFlywheelError("无法核对实例目录，请刷新后重试。")
        }
        self.identity = identity
        try validate(running: false)
    }

    func validate(running: Bool = true) throws {
        try Task.checkCancellation()
        guard library.hasListed, library.listError == nil,
              library.machines.contains(where: { $0.path == machine.path && $0.udid == machine.udid }),
              VPhoneFlywheelMachineReference.directoryIdentity(at: machine.path.url) == identity,
              try client.context(name: machine.name).executable == context.executable else {
            throw VPhoneFlywheelError("实例已改名、替换或核心绑定已改变，请刷新后重试。")
        }
        if running, library.state(of: machine.path) != .running {
            throw VPhoneFlywheelError("实例尚未运行；请先启动，或点击“准备网络与出口”。")
        }
    }

    func send(_ request: [String: Any], timeout: Int) async throws -> [String: Any] {
        try validate()
        let reply = try await VPhoneLaunchpadGuestSocket.send(request,
            socketPath: context.directory.appendingPathComponent("vphone.sock").path, timeout: timeout)
        try validate()
        guard let envelope = reply as? [String: Any], envelope["ok"] as? Bool == true,
              let result = envelope["result"] as? [String: Any] else {
            throw VPhoneFlywheelError("核心未返回有效结果；请检查绑定核心是否支持此操作。")
        }
        return result
    }

    func rpc(_ method: String, _ params: [String: Any], _ timeout: Int) async throws -> [String: Any] {
        try await send(["t": "rpc", "method": method, "params": params], timeout: timeout)
    }

    func route() async throws -> VPhoneFlywheelWebPage.Route {
        let status = try await send(["t": "network"], timeout: 10)
        guard status["device"] as? Bool == true else { throw VPhoneFlywheelError("实例没有网络设备，请准备 tunnel 网络。") }
        let mode = status["attachment"] as? String ?? "未知"
        guard mode == "tunnel" else { throw VPhoneFlywheelError("当前实际网络为 \(mode)，尚未接入业务出口；请点击“准备网络与出口”。") }
        guard status["link"] as? String == "up" else { throw VPhoneFlywheelError("实例网络链路已断开，请恢复连接后检查。") }
        let route: VPhoneFlywheelWebPage.Route
        if status["native_proxy_enabled"] as? Bool == true {
            route = .init(identity: "native", endpoint: status["native_proxy_endpoint"] as? String ?? "")
        } else {
            do {
                let value = try await VPhoneLaunchpadProxyServices.proxy.route(context: context)
                route = .init(identity: "clash:\(value.profile):\(value.process):\(value.selected)", endpoint: value.endpoint ?? "")
            } catch { throw VPhoneFlywheelError("DECODO 尚未就绪：" + error.localizedDescription + "。可点击“准备网络与出口”，或在代理出口中配置。") }
        }
        try validate()
        try route.validate()
        return route
    }

    func measure() async throws -> String {
        try await VPhoneFlywheelWebPage.measure(route: route, rpc: rpc)
    }

    /// Resolve the owner of this exact control socket, never a name/UDID match.
    func focus() async throws {
        try validate()
        let pids = try await RunningStateProbe(runner: SystemCLIRunner()).pids(
            diskImagePath: context.directory.appendingPathComponent("vphone.sock").path)
        try validate()
        let executable = context.executable.deletingLastPathComponent().appendingPathComponent("vphone-vm").resolvingSymlinksInPath()
        let applications = pids.compactMap { NSRunningApplication(processIdentifier: $0) }.filter {
            $0.executableURL?.resolvingSymlinksInPath() == executable
        }
        guard applications.count == 1, let app = applications.first else {
            throw VPhoneFlywheelError("无法定位该实例的虚拟机窗口，请手动切换。")
        }
        app.unhide()
        NSApp.yieldActivation(to: app)
        guard app.activate(options: [.activateAllWindows]) else {
            throw VPhoneFlywheelError("虚拟机窗口未能切到前台，请手动切换。")
        }
    }
}
