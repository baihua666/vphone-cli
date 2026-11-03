#if VPHONE_EXPERIMENTAL_NFC_NO_RF
import Foundation

enum VPhoneNFCResearchProbe {
    static let aid: [UInt8] = [0xf0, 0x56, 0x50, 0x48, 0x4f, 0x4e, 0x45, 1]
    static var select: [UInt8] { [0, 0xa4, 4, 0, UInt8(aid.count)] + aid }
    static func echo(_ nonce: [UInt8]) -> [UInt8] { [0x80, 1, 1, 0, UInt8(nonce.count)] + nonce }
    static func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

    static func run(backend: VPhoneNFCBackend) throws -> [String: Any] {
        let session = VPhoneNFCSession(backend: backend)
        defer { session.close() }
        let atr = try session.open(cid: 3, pipe: 0x16, mps: 17, credits: 1)
        try session.setMode(.apdu)
        let nonceA = Array(UUID().uuidString.utf8)
        let nonceB = Array(UUID().uuidString.utf8)
        var steps: [[String: Any]] = []
        for (name, request, expected) in [
            ("select", select, [UInt8(0x90), 0]),
            ("nonce-a", echo(nonceA), nonceA + [0x90, 0]),
            ("nonce-b", echo(nonceB), nonceB + [0x90, 0]),
            ("unsupported-ins", [UInt8(0x80), 0xff, 0, 0], [UInt8(0x6d), 0])
        ] {
            // Each transaction starts with an explicit credit if the preceding one consumed the last.
            var result: Result<[UInt8], VPhoneNFCError>?
            try session.begin(request) { result = $0 }
            while session.isPending {
                session.pump()
                // Explicit driver capacity grant, not acknowledgement that the applet finished.
                if session.isPending { try session.grant([0x60, 6, 3, 1, 3, 1]) }
            }
            guard let result else { throw VPhoneNFCError.invalidState }
            let response = try result.get()
            guard response == expected else { throw VPhoneNFCError.backend("\(name) returned \(hex(response))") }
            steps.append(["name": name, "request": hex(request), "response": hex(response),
                          "nci_tx": session.sent.count, "nci_rx": session.received.count])
        }
        return ["scope": "M0-host-model-real-jcardsim", "atr": hex(atr),
                "generation": session.generation, "model_completions": session.completions, "steps": steps]
    }
}
#endif
