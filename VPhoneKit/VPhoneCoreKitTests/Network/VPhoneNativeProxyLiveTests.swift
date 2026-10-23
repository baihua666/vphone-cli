import Foundation
import Testing
@testable import VPhoneCoreKit

/// Opt-in, consumes a small amount of real proxy traffic. Never opens a VM or writes its files.
struct VPhoneNativeProxyLiveTests {
    final class Wire: @unchecked Sendable {
        let queue = DispatchQueue(label: "native-live-wire")
        var packets: [VPhoneTCPSegment] = []
        var forwarder: VPhoneTCPForwarder!
        let flow: VPhoneTCPFlow
        init(_ config: VPhoneNativeProxy) {
            let parts = ProcessInfo.processInfo.environment["VPHONE_NATIVE_PROXY_TARGET"]!.split(separator: ".").map { UInt8($0)! }
            flow = VPhoneTCPFlow(sourceAddress: .init(192, 168, 127, 2), sourcePort: 51001,
                destinationAddress: .init(parts[0], parts[1], parts[2], parts[3]), destinationPort: 80,
                guestHardware: .init([2, 1, 2, 3, 4, 5]))
            forwarder = VPhoneTCPForwarder(queue: queue) { [weak self] _, segment in self?.packets.append(segment) }
            queue.sync { forwarder.start(); forwarder.setNativeProxy(config) }
        }
        func rotate(_ config: VPhoneNativeProxy) { queue.sync { forwarder.setNativeProxy(config); packets = [] } }
        func stop() { queue.sync { forwarder.stop() } }
        func request() throws -> String {
            func send(sequence: UInt32, ack: UInt32, flags: UInt8, payload: [UInt8] = []) {
                queue.sync { forwarder.receive(VPhoneTCPSegment(sourcePort: flow.sourcePort, destinationPort: 80,
                    sequenceNumber: sequence, acknowledgmentNumber: ack, flags: flags,
                    windowSize: 65535, payload: payload), for: flow) }
            }
            send(sequence: 1000, ack: 0, flags: VPhoneTCPFlags.syn)
            let until = Date().addingTimeInterval(20)
            var syn: VPhoneTCPSegment?
            while Date() < until {
                syn = queue.sync { packets.first { $0.hasSYN && $0.hasACK } }
                if syn != nil { break }; usleep(10000)
            }
            let sequence = try #require(syn).sequenceNumber + 1
            let request = Array("GET /json?provider=IPinfo HTTP/1.1\r\nHost: ip.decodo.com\r\nConnection: close\r\n\r\n".utf8)
            send(sequence: 1001, ack: sequence, flags: VPhoneTCPFlags.ack)
            send(sequence: 1001, ack: sequence, flags: VPhoneTCPFlags.ack | VPhoneTCPFlags.psh, payload: request)
            // Half-close the upload: the proxy must still deliver the response.
            send(sequence: UInt32(1001 + request.count), ack: sequence, flags: VPhoneTCPFlags.ack | VPhoneTCPFlags.fin)
            var body = Data()
            while Date() < until {
                let recorded = queue.sync { packets }
                var unique: [UInt32: [UInt8]] = [:]
                for packet in recorded where !packet.payload.isEmpty { unique[packet.sequenceNumber] = packet.payload }
                body = Data(unique.sorted { $0.key < $1.key }.flatMap(\.value))
                if !body.isEmpty {
                    send(sequence: UInt32(1002 + request.count), ack: sequence + UInt32(body.count), flags: VPhoneTCPFlags.ack)
                    if let boundary = body.range(of: Data("\r\n\r\n".utf8)),
                       let root = try? JSONSerialization.jsonObject(with: body.suffix(from: boundary.upperBound)) as? [String: Any],
                       let ip = (root["proxy"] as? [String: Any])?["ip"] as? String { return ip }
                }
                usleep(10000)
            }
            throw NSError(domain: "NativeProxyLiveTest", code: 1)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VPHONE_NATIVE_PROXY_FIXTURE"] != nil && ProcessInfo.processInfo.environment["VPHONE_NATIVE_PROXY_TARGET"] != nil))
    func twoIndependentStacksAndRotation() throws {
        let path = try #require(ProcessInfo.processInfo.environment["VPHONE_NATIVE_PROXY_FIXTURE"])
        let config = try VPhoneNativeProxy.load(URL(fileURLWithPath: path))
        var second = config; second.port = config.port == 32362 ? 32363 : 32362
        let a = Wire(config), b = Wire(second); defer { a.stop(); b.stop() }
        let firstIP = try a.request(), secondIP = try b.request()
        #expect(firstIP != secondIP)
        var rotated = config; rotated.port = 42362
        a.rotate(rotated)
        let rotatedIP = try a.request()
        #expect(rotatedIP != firstIP)
        b.rotate(second)
        let preservedIP = try b.request()
        #expect(preservedIP == secondIP)
        print("Native live egress: A=\(firstIP), B=\(secondIP), A rotated=\(rotatedIP), B unchanged=\(preservedIP)")
    }
}
