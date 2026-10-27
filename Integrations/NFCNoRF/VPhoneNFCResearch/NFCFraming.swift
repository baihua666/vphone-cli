#if VPHONE_EXPERIMENTAL_NFC_NO_RF
import Foundation

enum VPhoneNFCError: Error, Equatable {
    case invalidFrame, unsupported, invalidState, busy, timeout, disconnected, capacity, cancelled
    case backend(String)
}

enum VPhoneNFCCodec {
    static let maximumAPDU = 4096

    static func packets(_ bytes: [UInt8], cid: UInt8, pipe: UInt8, mps: Int) throws -> [[UInt8]] {
        guard (1...15).contains(cid), (2...127).contains(pipe), (1...255).contains(mps),
              !bytes.isEmpty, bytes.count <= maximumAPDU else { throw VPhoneNFCError.invalidFrame }
        var packets: [[UInt8]] = []
        var offset = 0
        while offset < bytes.count {
            let first = offset == 0
            let count = min(first ? 253 : 254, bytes.count - offset)
            let final = offset + count == bytes.count
            var hcp: [UInt8] = [pipe | (final ? 0x80 : 0)]
            if first { hcp.append(0x50) }
            hcp += bytes[offset..<offset + count]
            for start in stride(from: 0, to: hcp.count, by: mps) {
                let end = min(start + mps, hcp.count)
                packets.append([cid | (end < hcp.count ? 0x10 : 0), 0, UInt8(end - start)] + hcp[start..<end])
            }
            offset += count
        }
        return packets
    }
}

/// NCI stream boundaries are independent of socket reads and HCP fragment boundaries.
struct VPhoneNCIStreamDecoder {
    private var buffer: [UInt8] = []

    mutating func feed(_ bytes: [UInt8]) throws -> [[UInt8]] {
        guard buffer.count + bytes.count <= 8192 else { throw VPhoneNFCError.capacity }
        buffer += bytes
        var result: [[UInt8]] = []
        while buffer.count >= 3 {
            guard buffer[0] & 0xe0 == 0, buffer[1] == 0, buffer[2] > 0 else { throw VPhoneNFCError.invalidFrame }
            let count = Int(buffer[2]) + 3
            guard buffer.count >= count else { break }
            result.append(Array(buffer.prefix(count)))
            buffer.removeFirst(count)
        }
        return result
    }
}

struct VPhoneNFCHCPDecoder {
    let cid: UInt8
    let pipe: UInt8
    let mps: Int
    private var nci: [UInt8] = []
    private var data: [UInt8] = []
    private var started = false

    init(cid: UInt8, pipe: UInt8, mps: Int) {
        self.cid = cid; self.pipe = pipe; self.mps = mps
    }

    mutating func accept(_ packet: [UInt8]) throws -> [UInt8]? {
        guard packet.count >= 4, packet[0] & 0xe0 == 0, packet[0] & 0x0f == cid,
              packet[1] == 0, Int(packet[2]) == packet.count - 3,
              (1...mps).contains(Int(packet[2])) else { throw VPhoneNFCError.invalidFrame }
        nci += packet.dropFirst(3)
        guard nci.count <= 255 else { throw VPhoneNFCError.capacity }
        if packet[0] & 0x10 != 0 { return nil }
        let hcp = nci
        nci.removeAll(keepingCapacity: true)
        guard hcp[0] & 0x7f == pipe else { throw VPhoneNFCError.invalidFrame }
        if !started {
            guard hcp.count >= 3 else { throw VPhoneNFCError.invalidFrame }
            guard hcp[1] == 0x50 else { throw VPhoneNFCError.unsupported }
        } else if hcp.count < 2 { throw VPhoneNFCError.invalidFrame }
        data += hcp.dropFirst(started ? 1 : 2)
        started = true
        guard data.count <= VPhoneNFCCodec.maximumAPDU else { throw VPhoneNFCError.capacity }
        guard hcp[0] & 0x80 != 0 else { return nil }
        let response = data
        data.removeAll(keepingCapacity: true)
        started = false
        return response
    }
}

struct VPhoneNFCCreditSender {
    let cid: UInt8
    let packets: [[UInt8]]
    private(set) var credits: UInt8
    private(set) var sent = 0
    var hasRemaining: Bool { sent < packets.count }

    init(packets: [[UInt8]], cid: UInt8, credits: UInt8) {
        self.packets = packets; self.cid = cid; self.credits = credits
    }

    mutating func take() -> [UInt8]? {
        guard hasRemaining, credits > 0 else { return nil }
        let packet = packets[sent]
        sent += 1
        credits -= 1 // 0xff is finite in the recovered 23G90 path.
        return packet
    }

    mutating func grant(_ notification: [UInt8]) throws {
        guard notification.count == 6, Array(notification.prefix(4)) == [0x60, 6, 3, 1],
              notification[4] == cid else { throw VPhoneNFCError.invalidFrame }
        let sum = Int(credits) + Int(notification[5])
        // shortcut: M0 rejects overflow; do not claim all Comet arithmetic/profile branches.
        guard sum <= 255 else { throw VPhoneNFCError.invalidFrame }
        credits = UInt8(sum)
    }
}
#endif
