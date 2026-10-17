import Foundation

public struct VMNetworkStatus: Decodable, Sendable {
    public let device: Bool
    public let link: String?
    public let attachment: String?
    public let configured: String?
    public let guestIPv4: String?
    public let guestAddresses: [String]?
    public let egress: Egress?
    public var egressError: String?
    public var guestInterfaceIPv4: String? {
        guestAddresses?.first { $0.hasPrefix("en0 ") && !$0.contains(":") }
            .map { String($0.dropFirst(4)) }
    }

    public struct Egress: Decodable, Sendable {
        public let ip: String
        public let origin: String
        public let source: String
        public let checkedAt: String
        enum CodingKeys: String, CodingKey { case ip, origin, source; case checkedAt = "checked_at" }
    }
    enum CodingKeys: String, CodingKey {
        case device, link, attachment, configured, egress
        case guestIPv4 = "guest_ipv4", egressError = "egress_error"
        case guestAddresses = "guest_addresses"
    }
}

extension VPhoneCLIClient {
    public func networkStatus(name: String, probe: Bool = false) async throws -> VMNetworkStatus {
        var options = ["--json"]
        var unsupported = false
        if probe {
            // Query the pinned CLI, not the build/default binary.
            let help = try await runInstance(name: name, verb: "network", options: ["--help"])
            if help.contains("--probe") { options.append("--probe") }
            else { unsupported = true }
        }
        let text = try await runInstance(name: name, verb: "network", options: options)
        var status = try JSONDecoder().decode(VMNetworkStatus.self, from: Data(text.utf8))
        if let egress = status.egress {
            guard egress.origin == "guest", !egress.ip.isEmpty else {
                throw VPhoneCLIError.decodeFailed("Egress result was not measured by the guest")
            }
        }
        if unsupported { status.egressError = "此实例绑定的 CLI 尚不支持出口检测，请更新完整运行包。" }
        return status
    }

    public func supportsTunnel(name: String) async throws -> Bool {
        let help = try await runInstance(name: name, verb: "config", options: ["--help"])
        return help.contains("tunnel")
    }
}
