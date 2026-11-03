#if VPHONE_EXPERIMENTAL_NFC_NO_RF
import Foundation

@main
struct VPhoneNFCTestMain {
    static func main() {
        guard CommandLine.arguments.count == 3 else { exit(2) }
        let backend = VPhoneNFCBackend(java: CommandLine.arguments[1], classpath: CommandLine.arguments[2])
        do {
            let checks = VPhoneNFCChecks()
            try testNFCFraming(checks)
            let probe = try VPhoneNFCResearchProbe.run(backend: backend)
            let events = try testNFCIntegration(backend: backend, checks: checks)
            backend.stop()
            let report: [String: Any] = ["scope": "M0-host-model-only", "checks": checks.count,
                                       "probe": probe, "fault_and_boundary_tests": events, "passed": true]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } catch {
            backend.stop()
            FileHandle.standardError.write(Data("M0 test failure: \(error)\n".utf8))
            exit(1)
        }
    }
}
#endif
