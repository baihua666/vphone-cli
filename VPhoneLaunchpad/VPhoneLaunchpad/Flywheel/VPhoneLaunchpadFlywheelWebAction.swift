import Foundation
import Observation
import VPhoneFlywheel

@Observable @MainActor
final class VPhoneLaunchpadFlywheelWebAction {
    static let shared = VPhoneLaunchpadFlywheelWebAction()
    private(set) var active: VPhoneLaunchpadMachinePath?
    private(set) var messages: [VPhoneLaunchpadMachinePath: String] = [:]
    @ObservationIgnored let focus: (VPhoneLaunchpadFlywheelGuest) async throws -> Void

    init(focus: @escaping (VPhoneLaunchpadFlywheelGuest) async throws -> Void = { try await $0.focus() }) {
        self.focus = focus
    }

    func clearMessage(for path: VPhoneLaunchpadMachinePath) { messages[path] = nil }

    func exclusively<T>(on path: VPhoneLaunchpadMachinePath, operation: () async throws -> T) async throws -> T {
        guard active == nil else { throw VPhoneFlywheelError("已有业务操作正在执行，请稍后重试。") }
        active = path
        defer { active = nil }
        return try await operation()
    }

    func open(url: String, includeIP: Bool = true, parameters: [VPhoneFlywheelURLParameter] = [],
              machine: VPhoneLaunchpadMachine, library: VPhoneLaunchpadMachineLibrary) {
        guard active == nil else { return }
        active = machine.path
        VPhoneLaunchpadFlywheelNetwork.shared.invalidate(machine.path)
        messages[machine.path] = "正在核对实例与 DECODO 出口…"
        Task {
            defer { active = nil }
            do {
                let guest = try VPhoneLaunchpadFlywheelGuest(machine: machine, library: library)
                let ip = try await VPhoneFlywheelWebPage.open(url, includeIP: includeIP, parameters: parameters,
                    route: guest.route, rpc: guest.rpc,
                    onProgress: { messages[machine.path] = $0 })
                VPhoneLaunchpadFlywheelNetwork.shared.record(ip, for: machine.path)
                let success = "Safari 打开请求已完成 · " + (includeIP ? "已附加 ip 参数" : "未附加 ip 参数")
                messages[machine.path] = success
                do {
                    try guest.validate()
                    try await focus(guest)
                } catch {
                    messages[machine.path] = success + "；窗口切换失败：" + VPhoneLaunchpadError.message(for: error)
                }
            } catch { messages[machine.path] = "打开失败：" + VPhoneLaunchpadError.message(for: error) }
        }
    }
}
