import Foundation
import SystemConfiguration

#if VPHONE_CUSTOM_NATIVE_INTERFACE_SELECTION
/// Host-local interface discovery. Never assume this Mac's BSD name on another Mac.
enum NativePhysicalNetwork {
    struct Interface: Equatable {
        let device: String
        let kind: String
        let hasIPv4: Bool
    }

    static func choose(_ interfaces: [Interface], primary: String?, kind: String? = nil) -> Interface? {
        let eligible = interfaces.filter { kind == nil || $0.kind == kind }
        return eligible.first { $0.device == primary && $0.hasIPv4 }
            ?? eligible.first { $0.hasIPv4 }
            ?? (eligible.count == 1 ? eligible.first : nil)
    }

    static func preferred(kind: String? = nil) -> Interface? {
        let store = SCDynamicStoreCreate(nil, "vphone-native-interface" as CFString, nil, nil)
        let primary = store.flatMap {
            (SCDynamicStoreCopyValue($0, "State:/Network/Global/IPv4" as CFString) as? [String: Any])?["PrimaryInterface"] as? String
        }
        let interfaces = (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []).compactMap { value -> Interface? in
            guard let device = SCNetworkInterfaceGetBSDName(value) as String? else { return nil }
            let type = SCNetworkInterfaceGetInterfaceType(value) as String?
            let kind: String
            if type == kSCNetworkInterfaceTypeIEEE80211 as String { kind = "wifi" }
            else if type == kSCNetworkInterfaceTypeEthernet as String { kind = "ethernet" }
            else { return nil }
            let ipv4 = store.flatMap { SCDynamicStoreCopyValue($0, "State:/Network/Interface/\(device)/IPv4" as CFString) as? [String: Any] }
            let addresses = ipv4?["Addresses"] as? [String] ?? []
            return Interface(device: device, kind: kind, hasIPv4: addresses.contains { !$0.hasPrefix("169.254.") && !$0.isEmpty })
        }
        return choose(interfaces, primary: primary, kind: kind)
    }
}
#endif
