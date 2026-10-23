import Foundation

/// Automation policy; the creation pipeline knows only its injected hook.
@MainActor
enum VPhoneDeviceInitialization {
    struct Failure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func run(
        rpc: (String, [String: Any], Int) async throws -> [String: Any],
        wait: (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        onProgress: (String) -> Void = { _ in },
    ) async throws {
        try Task.checkCancellation()
        let before = try await rpc("display.auto_lock", [:], 10)
        guard before["set_supported"] as? Bool == true else {
            throw Failure(message: "The guest environment cannot set Auto-Lock. Update it with a compatible Core Bundle, then retry initialization.")
        }

        onProgress("Unlocking the device…")
        try requireUnlocked(await rpc("screen.unlock", ["timeout": 60], 70))
        onProgress("Setting Auto-Lock to Never…")
        try requireNever(await rpc("display.auto_lock", ["never": true], 20))
        onProgress("Restarting SpringBoard to apply the Lock Screen setting…")
        _ = try await rpc("system.respring", ["force": true], 40)
        try requireUnlocked(await rpc("screen.unlock", ["timeout": 60], 70))

        onProgress("Verifying the idle screen for 120 seconds; leave the device untouched…")
        let deadline = now() + 120
        while now() < deadline {
            try Task.checkCancellation()
            try await wait(min(5, max(0, deadline - now())))
            // Reading state does not inject input or keep the screen awake.
            try requireUnlocked(await rpc("device.screen", [:], 10))
        }
        try Task.checkCancellation()
        try requireNever(await rpc("display.auto_lock", [:], 10))
        onProgress("Verified: Auto-Lock is Never and the idle device stayed unlocked with its display on.")
    }

    private static func requireUnlocked(_ state: [String: Any]) throws {
        guard state["locked"] as? Bool == false, state["screen_off"] as? Bool == false else {
            throw Failure(message: "The device is locked, dark, or its screen state could not be read. Complete device setup/unlock if needed, then retry initialization.")
        }
    }

    private static func requireNever(_ state: [String: Any]) throws {
        guard state["never"] as? Bool == true,
              (state["auto_lock_seconds"] as? NSNumber)?.intValue == Int(Int32.max),
              (state["lock_screen_minimum_seconds"] as? NSNumber)?.intValue == Int(Int32.max)
        else {
            throw Failure(message: "Auto-Lock Never or its Lock Screen idle setting did not persist. Check the guest settings and retry initialization.")
        }
    }
}
