import ArgumentParser
import Foundation
import VPhoneCoreKit

// MARK: - network

/// The NIC of a running VM: show it, or unplug and replug it. Nothing here is
/// saved; `vm config` changes what the next launch uses, and moving to another
/// network needs a restart (see `VPhoneVirtualMachine.setNetworkLink`).
struct VPhoneVirtualMachineNetworkCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "network",
        abstract: "Show a running VM's network link, or unplug and replug it",
        discussion: """
        Without options, prints the NIC's state. --link down unplugs the guest's cable and \
        --link up plugs it back in; the guest sees the link drop and come back. Nothing is \
        saved. To move the VM to another network, change it with vm config and restart it.
        """,
    )

    @OptionGroup var lib: VPhoneLibraryOption
    @Argument(help: "VM name") var name: String?
    @Option(name: .long, help: "up | down") var link: String?
    @Flag(name: .shortAndLong, help: "Emit JSON") var json = false
    @Flag(name: .long, help: "Check public IPv4 from the guest via HTTPS (api.ipify.org)") var probe = false

    @Option(name: .long, help: "Experimental HTTPS proxy configuration (0600 JSON); empty restores host/Clash routing")
    var nativeProxyFile: String?

    func run() throws {
        guard nativeProxyFile == nil || (!probe && link == nil) else { throw ValidationError("Proxy changes cannot be combined with probe/link changes") }
        guard !probe || link == nil else { throw ValidationError("--probe cannot change the network link.") }
        if let link, link != "up", link != "down" {
            throw ValidationError("--link must be up or down.")
        }
        let name = try VPhoneVirtualMachineSelection.resolveExisting(name, in: lib.library)
        let bundle = try lib.library.bundle(named: name)
        let socketPath = bundle.url.appendingPathComponent("vphone.sock").path

        var request: [String: Any] = ["t": "network"]
        request["link"] = link
        if let path = nativeProxyFile {
            guard let before = VPhoneHostAutomationProbe.send(["t": "network"], socketPath: socketPath, timeout: 10),
                  let status = before["result"] as? [String: Any], status["native_proxy_supported"] as? Bool == true else {
                throw ValidationError("Running core does not support native proxy; existing routing unchanged")
            }
            if !path.isEmpty {
                guard path.hasPrefix("/") else { throw ValidationError("Proxy configuration must be an absolute path") }
                _ = try VPhoneNativeProxy.load(URL(fileURLWithPath: path))
            }
            request["native_proxy_file"] = path
        }
        guard let reply = VPhoneHostAutomationProbe.send(request, socketPath: socketPath, timeout: 10) else {
            throw ValidationError("\(name) is not running, or its control socket does not answer. Start it with vm launch.")
        }
        guard reply["ok"] as? Bool == true, var status = reply["result"] as? [String: Any] else {
            throw ValidationError(reply["error"] as? String ?? "the VM refused the request")
        }

        let guest = VPhoneHostAutomationProbe.send(
            ["t": "rpc", "method": "device.network"], socketPath: socketPath, timeout: 3)
        status["guest_addresses"] = (guest?["result"] as? [String: Any])?["addresses"]
        if probe {
            let reply = VPhoneHostAutomationProbe.send(
                ["t": "rpc", "method": "network.egress"], socketPath: socketPath, timeout: 25)
            if reply?["ok"] as? Bool == true, let result = reply?["result"] as? [String: Any] {
                status["egress"] = result
            } else {
                status["egress_error"] = reply?["error"] as? String
                    ?? "Guest egress check timed out or the guest disconnected."
            }
        }

        if json {
            let data = try JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            return
        }
        guard status["device"] as? Bool == true else {
            print("\(name): no network device")
            return
        }
        print("link:       \(status["link"] as? String ?? "?")")
        print("attached:   \(status["attachment"] as? String ?? "?")")
        if let egress = status["egress"] as? [String: Any] {
            print("public IPv4: \(egress["ip"] as? String ?? "?") (guest HTTPS)")
        }
        if let error = status["egress_error"] as? String { print("egress check failed: \(error)") }
        if let configured = status["configured"] as? String {
            print("configured: \(configured)")
        }
        if let guest = status["guest_ipv4"] as? String, !guest.isEmpty {
            print("guest:      \(guest)")
        }
        for forward in status["forwards"] as? [String] ?? [] {
            print("forward:    \(forward)")
        }
        if let name = status["local_host_name"] as? String, !name.isEmpty {
            print("mdns:       \(name)")
        }
    }
}
