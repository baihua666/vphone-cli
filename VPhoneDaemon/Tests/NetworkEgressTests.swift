import Foundation

// The production probe is compiled unchanged; only the daemon's error type is substituted.
enum GuestAPIError: Error { case operationFailed(String) }

@main enum NetworkEgressTests {
    static func main() throws {
        let valid = try GuestNetworkEgress.parse(Data(#"{"ip":"8.8.8.8"}"#.utf8))
        precondition(valid == "8.8.8.8")
        let invalid = ["", "<html>error</html>", "{}", #"{"ip":42}"#,
            #"{"ip":"::1"}"#, #"{"ip":"127.0.0.1"}"#, #"{"ip":"192.168.1.2"}"#,
            #"{"ip":"172.16.0.1"}"#, #"{"ip":"100.64.0.1"}"#, #"{"ip":"169.254.1.1"}"#,
            #"{"ip":"10.0.0.1"}"#, #"{"ip":"0.0.0.0"}"#, #"{"ip":"255.255.255.255"}"#,
            #"{"ip":"8.8.8.8 trailing"}"#, String(repeating: "x", count: 4097)]
        for value in invalid {
            do {
                _ = try GuestNetworkEgress.parse(Data(value.utf8))
                fatalError("Accepted invalid response: \(value.prefix(80))")
            } catch is GuestAPIError {}
        }
        print("Guest egress response tests passed (16 cases)")
    }
}
