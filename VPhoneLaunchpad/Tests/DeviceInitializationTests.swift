import Foundation

@MainActor
final class InitializationGuest {
    var time: TimeInterval = 0
    var methods: [String] = []
    var supportsSetting = true
    var persists = true
    var lockedAt: TimeInterval?
    var disconnectsAt: TimeInterval?
    var respringFails = false
    var screenReadable = true
    var never = false

    func rpc(_ method: String, _ params: [String: Any], _ timeout: Int) async throws -> [String: Any] {
        methods.append(method)
        if let disconnectsAt, time >= disconnectsAt {
            throw VPhoneDeviceInitialization.Failure(message: "disconnected")
        }
        switch method {
        case "display.auto_lock":
            if params["never"] as? Bool == true, persists { never = true }
            return ["set_supported": supportsSetting, "never": never,
                    "auto_lock_seconds": never ? Int(Int32.max) : 30,
                    "lock_screen_minimum_seconds": never ? Int(Int32.max) : 6]
        case "screen.unlock", "device.screen":
            if !screenReadable { return [:] }
            let locked = lockedAt.map { time >= $0 } ?? false
            return ["locked": locked, "screen_off": locked]
        case "system.respring":
            precondition(params["force"] as? Bool == true)
            if respringFails { throw VPhoneDeviceInitialization.Failure(message: "respring failed") }
            return [:]
        default:
            preconditionFailure("Unexpected RPC: \(method)")
        }
    }

    func initialize() async throws {
        try await VPhoneDeviceInitialization.run(rpc: rpc, wait: { self.time += $0 }, now: { self.time })
    }
}

@main
@MainActor
struct DeviceInitializationTests {
    static func expectFailure(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            preconditionFailure("Expected initialization to fail")
        } catch is VPhoneDeviceInitialization.Failure {
        } catch { preconditionFailure("Unexpected failure: \(error)") }
    }

    static func main() async throws {
        let success = InitializationGuest()
        try await success.initialize()
        precondition(success.time == 120)
        precondition(Array(success.methods.prefix(5)) == [
            "display.auto_lock", "screen.unlock", "display.auto_lock", "system.respring", "screen.unlock",
        ])
        precondition(success.methods.filter { $0 == "device.screen" }.count == 24)
        precondition(success.methods.last == "display.auto_lock")

        let old = InitializationGuest()
        old.supportsSetting = false
        await expectFailure { try await old.initialize() }
        precondition(old.methods == ["display.auto_lock"], "Old guests must fail before writes")

        let rejected = InitializationGuest()
        rejected.persists = false
        await expectFailure { try await rejected.initialize() }
        precondition(!rejected.methods.contains("system.respring"))

        for unreadable in [false, true] {
            let guest = InitializationGuest()
            guest.lockedAt = 35
            guest.screenReadable = !unreadable
            await expectFailure { try await guest.initialize() }
            precondition(guest.time < 120)
        }
        for duringRespring in [false, true] {
            let guest = InitializationGuest()
            guest.respringFails = duringRespring
            if !duringRespring { guest.disconnectsAt = 45 }
            await expectFailure { try await guest.initialize() }
        }

        let retry = InitializationGuest()
        retry.respringFails = true
        await expectFailure { try await retry.initialize() }
        retry.respringFails = false
        retry.methods = []
        try await retry.initialize()
        try await retry.initialize()
        precondition(retry.time == 240 && retry.methods.filter { $0 == "system.respring" }.count == 2)

        let changed = InitializationGuest()
        await expectFailure {
            try await VPhoneDeviceInitialization.run(rpc: changed.rpc, wait: {
                changed.time += $0
                if changed.time >= 120 { changed.never = false }
            }, now: { changed.time })
        }

        // Use the production async timer here: cancellation must interrupt it.
        let cancelled = InitializationGuest()
        let task = Task { try await VPhoneDeviceInitialization.run(rpc: cancelled.rpc) }
        while !cancelled.methods.contains("system.respring") { await Task.yield() }
        task.cancel()
        do {
            try await task.value
            preconditionFailure("Cancelled initialization passed")
        } catch is CancellationError {}
        precondition(!cancelled.methods.contains("device.screen"))
        print("Device policy tests passed: 120 s idle observation, old capability, failed persistence, screen state, disconnect, respring, retry, final readback, cancellation")
    }
}
