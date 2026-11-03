import Foundation
import Observation
import VPhoneFlywheel
import VPhoneWSCore

@Observable @MainActor
final class VPhoneLaunchpadFlywheelNetwork {
    static let shared = VPhoneLaunchpadFlywheelNetwork()
    var city = UserDefaults.standard.string(forKey: "flywheel.decodo.city") ?? "new_york_city" {
        didSet { UserDefaults.standard.set(city, forKey: "flywheel.decodo.city") }
    }
    var device = UserDefaults.standard.string(forKey: "flywheel.decodo.device") ?? "en1" {
        didSet { UserDefaults.standard.set(device, forKey: "flywheel.decodo.device") }
    }
    var credentialsPath = UserDefaults.standard.string(forKey: "flywheel.decodo.credentialsPath")
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".vphone/decodo-isp.json").path {
        didSet { UserDefaults.standard.set(credentialsPath, forKey: "flywheel.decodo.credentialsPath") }
    }
    private(set) var messages: [VPhoneLaunchpadMachinePath: String] = [:]
    struct Measurement {
        let ip: String
        let checkedAt: Date
    }
    private(set) var measurements: [VPhoneLaunchpadMachinePath: Measurement] = [:]

    func invalidate(_ path: VPhoneLaunchpadMachinePath) {
        measurements[path] = nil
        messages[path] = nil
        VPhoneLaunchpadFlywheelWebAction.shared.clearMessage(for: path)
    }

    func record(_ ip: String, for path: VPhoneLaunchpadMachinePath, at date: Date = Date()) {
        measurements[path] = Measurement(ip: ip, checkedAt: date)
        messages[path] = nil
    }

    /// Publish the guest measurement already made by the native workflow. Never probe twice.
    func performMeasured(on path: VPhoneLaunchpadMachinePath,
                         operation: () async -> (ip: String?, message: String)) async {
        do {
            try await VPhoneLaunchpadFlywheelWebAction.shared.exclusively(on: path) {
                invalidate(path)
                messages[path] = "正在检测虚拟机公网 IP…"
                let result = await operation()
                if let ip = result.ip {
                    record(ip, for: path)
                } else {
                    messages[path] = result.message
                }
            }
        } catch {
            // An overlapping operation owns its existing measurement and progress.
        }
    }

    func check(_ machine: VPhoneLaunchpadMachine, library: VPhoneLaunchpadMachineLibrary) async {
        guard VPhoneLaunchpadFlywheelWebAction.shared.active == nil else { return }
        let path = machine.path
        invalidate(path)
        if library.state(of: path) != .running {
            messages[path] = "未启动 · 点击“准备网络与出口”可启动并检查 DECODO。"
            return
        }
        messages[path] = "正在检查实际网络与 guest 出口…"
        do {
            let ip = try await VPhoneLaunchpadFlywheelWebAction.shared.exclusively(on: path) {
                try await VPhoneLaunchpadFlywheelGuest(machine: machine, library: library).measure()
            }
            VPhoneLaunchpadFlywheelWebAction.shared.clearMessage(for: path)
            record(ip, for: path)
            messages[path] = "检查通过"
        } catch { messages[path] = "网络未就绪：" + VPhoneLaunchpadError.message(for: error) }
    }

    @discardableResult
    func prepare(_ machine: VPhoneLaunchpadMachine, library: VPhoneLaunchpadMachineLibrary) async throws -> String {
        try await VPhoneLaunchpadFlywheelWebAction.shared.exclusively(on: machine.path) {
            let path = machine.path
            invalidate(path)
            await library.refresh()
            guard let current = library.machines.first(where: { $0.path == path && $0.udid == machine.udid }) else {
                throw VPhoneFlywheelError("实例已变化，请刷新后重试网络准备。")
            }
            let guest = try VPhoneLaunchpadFlywheelGuest(machine: current, library: library)
            do {
                guard try await guest.client.supportsTunnel(name: machine.name) else {
                    throw VPhoneFlywheelError("此实例绑定的核心不支持 tunnel；请先选择兼容核心。")
                }
                try guest.validate(running: false)
                let running = library.state(of: path) == .running
                guard running || library.state(of: path) == .stopped else {
                    throw VPhoneFlywheelError("实例正在执行其它操作，请完成后重试。")
                }
                let ip = try await VPhoneFlywheelNetworkPreparation.run(
                    isTunnel: current.network.mode == "tunnel", isRunning: running,
                    stop: {
                        try guest.validate()
                        await library.stop(path)
                        await library.refresh()
                        guard library.state(of: path) == .stopped else { throw VPhoneFlywheelError("实例未正常停止，未修改网络。") }
                    }, setTunnel: {
                        try guest.validate(running: false)
                        try await guest.client.setConfig(name: machine.name, cpu: nil, memoryMB: nil, network: "tunnel")
                        await library.refresh()
                        try guest.validate(running: false)
                    }, start: {
                        try guest.validate(running: false)
                        await library.start(path)
                        await library.refresh()
                        try guest.validate()
                    }, connectDecodo: {
                        // Running can precede the guest control connection on a cold boot.
                        var connected = false
                        for _ in 0..<60 {
                            try guest.validate()
                            if let status = try? await guest.client.networkStatus(name: machine.name),
                               status.link == "up", status.guestInterfaceIPv4 != nil {
                                try guest.validate()
                                connected = true
                                break
                            }
                            try await Task.sleep(for: .seconds(1))
                        }
                        guard connected else { throw VPhoneFlywheelError("Guest 尚未取得 IPv4 或可用链路，请稍后独立重试网络准备。") }
                        if (try? await guest.route()) != nil { return }
                        let native = NativeDecodoController(client: guest.client, name: machine.name)
                        native.credentialsPath = credentialsPath
                        native.city = city
                        native.device = device
                        await native.refresh()
                        guard native.supported else { throw VPhoneFlywheelError("当前运行核心不支持原生 DECODO；请先在代理出口中配置 Clash / DECODO 后重试。") }
                        await native.rotate()
                        try guest.validate()
                        guard native.enabled, let expectedIP = native.location?.ip else {
                            throw VPhoneFlywheelError(native.message)
                        }
                        // Keep the applied endpoint while iOS finishes updating its network path.
                        if native.guestIP != expectedIP {
                            messages[path] = "DECODO 已应用，正在等待 guest 网络路由就绪…"
                            var verified = false
                            for _ in 0..<6 {
                                try guest.validate()
                                if let ip = try? await guest.measure(), ip == expectedIP { verified = true; break }
                                try await Task.sleep(for: .seconds(2))
                            }
                            guard verified else { throw VPhoneFlywheelError("DECODO 已应用，但 guest 尚未确认相同出口；请独立重试网络准备。") }
                        }
                    }, verify: {
                        let expected = try await guest.route()
                        let ip = try await VPhoneFlywheelNetworkPreparation.verify(check: guest.measure)
                        guard try await guest.route() == expected else {
                            throw VPhoneFlywheelError("验证期间出口发生变化，请重新准备。")
                        }
                        return ip
                    },
                    onProgress: { messages[path] = $0 })
                messages[path] = "准备通过"
                record(ip, for: path)
                VPhoneLaunchpadFlywheelWebAction.shared.clearMessage(for: path)
                return ip
            } catch {
                messages[path] = "网络准备未完成：" + VPhoneLaunchpadError.message(for: error)
                throw error
            }
        }
    }
}
