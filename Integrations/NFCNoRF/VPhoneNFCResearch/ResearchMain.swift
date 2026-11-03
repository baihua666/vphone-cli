import Foundation

@main
struct VPhoneNFCResearchMain {
    static func main() {
        #if VPHONE_EXPERIMENTAL_NFC_NO_RF
        guard CommandLine.arguments.count == 3 else {
            print("usage: research <JDK17-java-path> <wrapper-classes:jcardsim-jar>")
            exit(2)
        }
        do {
            let backend = VPhoneNFCBackend(java: CommandLine.arguments[1], classpath: CommandLine.arguments[2])
            defer { backend.stop() }
            let report = try VPhoneNFCResearchProbe.run(backend: backend)
            let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: json, as: UTF8.self))
        } catch {
            FileHandle.standardError.write(Data("M0 failed: \(error)\n".utf8))
            exit(1)
        }
        #else
        print("VPHONE_EXPERIMENTAL_NFC_NO_RF is disabled; no experimental backend or listener compiled.")
        #endif
    }
}
