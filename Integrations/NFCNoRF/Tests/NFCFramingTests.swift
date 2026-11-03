#if VPHONE_EXPERIMENTAL_NFC_NO_RF
import Foundation

func testNFCFraming(_ checks: VPhoneNFCChecks) throws {
    for count in [1, 2, 252, 253, 254, 255, 506, 507, 600, 4096] {
        let input = (0..<count).map { UInt8($0 & 255) }
        for mps in [1, 17, 64, 255] {
            let frames = try VPhoneNFCCodec.packets(input, cid: 3, pipe: 0x16, mps: mps)
            var stream = VPhoneNCIStreamDecoder()
            var hcp = VPhoneNFCHCPDecoder(cid: 3, pipe: 0x16, mps: mps)
            var outputs: [[UInt8]] = []
            let wire = frames.flatMap { $0 }
            for offset in stride(from: 0, to: wire.count, by: 7) {
                for frame in try stream.feed(Array(wire[offset..<min(offset + 7, wire.count)])) {
                    if let bytes = try hcp.accept(frame) { outputs.append(bytes) }
                }
            }
            try checks.check(outputs == [input], "HCP/NCI/stream roundtrip \(count)/\(mps)")
        }
    }
    let bytes = [UInt8](repeating: 0xaa, count: 254)
    let boundary = try VPhoneNFCCodec.packets(bytes, cid: 3, pipe: 0x16, mps: 255)
    try checks.check(boundary.count == 2, "254 bytes must cross HCP boundary")
    try checks.check(Array(boundary[0].prefix(5)) == [3, 0, 255, 0x16, 0x50], "first HCP fragment is not final")
    try checks.check(boundary[1] == [3, 0, 2, 0x96, 0xaa], "continuation omits type/ins and sets final")
    let single = try VPhoneNFCCodec.packets(Array(bytes.prefix(253)), cid: 3, pipe: 0x16, mps: 255)
    try checks.check(single.count == 1 && single[0][3] == 0x96, "253-byte HCP payload is final")
    let split = try VPhoneNFCCodec.packets([1, 2], cid: 3, pipe: 0x16, mps: 3)
    try checks.check(split == [[0x13, 0, 3, 0x96, 0x50, 1], [3, 0, 1, 2]], "NCI PBF is independent of HCP final")

    var credits = VPhoneNFCCreditSender(packets: boundary, cid: 3, credits: 0)
    try checks.check(credits.take() == nil && credits.sent == 0, "credit zero pauses")
    try credits.grant([0x60, 6, 3, 1, 3, 0])
    try checks.check(credits.take() == nil, "zero delta does not resume")
    try checks.fails(.invalidFrame) { try credits.grant([0x60, 6, 3, 1, 4, 1]) }
    try credits.grant([0x60, 6, 3, 1, 3, 1])
    try checks.check(credits.take() == boundary[0] && credits.take() == nil && credits.sent == 1, "one credit accepts one frame")
    try credits.grant([0x60, 6, 3, 1, 3, 1])
    try checks.check(credits.take() == boundary[1] && !credits.hasRemaining, "resume without duplicate")
    var finite = VPhoneNFCCreditSender(packets: boundary, cid: 3, credits: 255)
    _ = finite.take()
    try checks.check(finite.credits == 254, "ff is finite")
    try checks.fails(.invalidFrame) { try finite.grant([0x60, 6, 3, 1, 3, 2]) }
    try checks.fails(.invalidFrame) { try finite.grant([0x60, 6, 5, 2, 3, 1, 4, 1]) }

    for invalid in [[UInt8(4), 0, 3, 0x96, 0x50, 1], [3, 0, 3, 0x97, 0x50, 1],
                    [3, 0, 4, 0x96, 0x50, 1], [0x23, 0, 3, 0x96, 0x50, 1]] {
        var decoder = VPhoneNFCHCPDecoder(cid: 3, pipe: 0x16, mps: 17)
        try checks.fails(.invalidFrame) { _ = try decoder.accept(invalid) }
    }
    var anyOK = VPhoneNFCHCPDecoder(cid: 3, pipe: 0x16, mps: 17)
    try checks.fails(.unsupported) { _ = try anyOK.accept([3, 0, 3, 0x96, 0x80, 0]) }
    var stream = VPhoneNCIStreamDecoder()
    try checks.fails(.invalidFrame) { _ = try stream.feed([0x20, 0, 1, 0]) }
    var partial = VPhoneNFCHCPDecoder(cid: 3, pipe: 0x16, mps: 255)
    try checks.check(try partial.accept(boundary[0]) == nil, "partial HCP cannot produce response")
    var other = VPhoneNFCHCPDecoder(cid: 7, pipe: 0x25, mps: 17)
    let changed = try VPhoneNFCCodec.packets([0x90, 0], cid: 7, pipe: 0x25, mps: 17)
    try checks.check(try other.accept(changed[0]) == [0x90, 0], "CID/pipe are configurable, not hardwired NFCEE ID")
    try checks.fails(.invalidFrame) { _ = try VPhoneNFCCodec.packets([1], cid: 0, pipe: 0x16, mps: 17) }
    try checks.fails(.invalidFrame) { _ = try VPhoneNFCCodec.packets([1], cid: 3, pipe: 1, mps: 17) }
    try checks.fails(.invalidFrame) { _ = try VPhoneNFCCodec.packets([1], cid: 3, pipe: 0x16, mps: 0) }
}
#endif
