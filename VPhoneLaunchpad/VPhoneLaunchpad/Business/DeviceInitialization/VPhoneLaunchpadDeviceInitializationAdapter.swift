import Foundation

/// The only adapter from the automation policy to Launchpad's machine context.
@MainActor
enum VPhoneLaunchpadDeviceInitializationAdapter {
    static func make(bundles: VPhoneLaunchpadCoreBundle) -> VPhoneLaunchpadCreationPipeline.DeviceInitializer {
        { machine, version, output in
            guard let commandLine = bundles.commandLine(version: version) else {
                throw VPhoneLaunchpadError("The machine's bound Core Bundle is unavailable.")
            }
            let socket = machine.url.appendingPathComponent("vphone.sock").path
            try await VPhoneDeviceInitialization.run(rpc: { method, params, timeout in
                try Task.checkCancellation()
                let reply = try await VPhoneLaunchpadGuestSocket.send(
                    ["t": "rpc", "method": method, "params": params], socketPath: socket, timeout: timeout,
                )
                try Task.checkCancellation()
                guard let envelope = reply as? [String: Any], envelope["ok"] as? Bool == true,
                      let result = envelope["result"] as? [String: Any]
                else { throw VPhoneLaunchpadError("The guest initialization reply could not be read.") }
                return result
            }, onProgress: output)
            try Task.checkCancellation()
            try await commandLine.runChecked(
                ["vm", "config", machine.name, "--unlock-at-startup", "on"] + machine.libraryArguments,
                onLine: output,
            )
        }
    }
}
