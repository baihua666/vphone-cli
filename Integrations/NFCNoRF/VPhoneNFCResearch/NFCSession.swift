#if VPHONE_EXPERIMENTAL_NFC_NO_RF
import Foundation

/// Single-threaded M0 contract driver/controller model; not an Apple callback ABI.
final class VPhoneNFCSession {
    enum Mode { case off, apdu }
    struct Connection {
        let cid: UInt8
        let pipe: UInt8
        let mps: Int
    }
    private final class Pending {
        let generation: UInt64
        let deadline: Double
        let capacity: Int
        let completion: (Result<[UInt8], VPhoneNFCError>) -> Void
        var sender: VPhoneNFCCreditSender
        var request: VPhoneNFCHCPDecoder
        var response: VPhoneNFCHCPDecoder

        init(generation: UInt64, deadline: Double, capacity: Int, connection: Connection,
             sender: VPhoneNFCCreditSender, completion: @escaping (Result<[UInt8], VPhoneNFCError>) -> Void) {
            self.generation = generation; self.deadline = deadline; self.capacity = capacity
            self.sender = sender; self.completion = completion
            request = VPhoneNFCHCPDecoder(cid: connection.cid, pipe: connection.pipe, mps: connection.mps)
            response = request
        }
    }

    let backend: VPhoneNFCBackend
    private var connection: Connection?
    private var pending: Pending?
    private(set) var generation: UInt64 = 0
    private(set) var mode = Mode.off
    private(set) var credits: UInt8 = 0
    private(set) var completions = 0
    private(set) var ignoredOldResponses = 0
    private(set) var sent: [[UInt8]] = []
    private(set) var received: [[UInt8]] = []
    var isPending: Bool { pending != nil }

    init(backend: VPhoneNFCBackend) { self.backend = backend }

    @discardableResult
    func open(cid: UInt8, pipe: UInt8, mps: Int, credits: UInt8) throws -> [UInt8] {
        guard pending == nil else { throw VPhoneNFCError.busy }
        _ = try VPhoneNFCCodec.packets([0], cid: cid, pipe: pipe, mps: mps)
        invalidate()
        let atr = try backend.start()
        connection = Connection(cid: cid, pipe: pipe, mps: mps)
        self.credits = credits
        return atr
    }

    func setMode(_ value: Mode) throws {
        guard pending == nil else { throw VPhoneNFCError.busy }
        if value == .apdu, connection == nil || !backend.isConnected { throw VPhoneNFCError.invalidState }
        mode = value
    }

    func begin(_ apdu: [UInt8], capacity: Int = 4096, timeout: Double = 2,
               completion: @escaping (Result<[UInt8], VPhoneNFCError>) -> Void) throws {
        guard pending == nil else { throw VPhoneNFCError.busy }
        guard mode == .apdu, let connection, backend.isConnected else { throw VPhoneNFCError.invalidState }
        guard (4...VPhoneNFCCodec.maximumAPDU).contains(apdu.count), (1...4096).contains(capacity),
              timeout.isFinite, (0.001...30).contains(timeout) else { throw VPhoneNFCError.invalidFrame }
        let packets = try VPhoneNFCCodec.packets(apdu, cid: connection.cid, pipe: connection.pipe, mps: connection.mps)
        sent.removeAll(); received.removeAll()
        pending = Pending(generation: generation, deadline: VPhoneNFCBackend.now + timeout,
                          capacity: capacity, connection: connection,
                          sender: VPhoneNFCCreditSender(packets: packets, cid: connection.cid, credits: credits),
                          completion: completion)
    }

    /// Caller drives credit notifications; zero credit never auto-refills or executes the APDU.
    func grant(_ notification: [UInt8]) throws {
        guard let pending else { throw VPhoneNFCError.invalidState }
        try pending.sender.grant(notification)
        credits = pending.sender.credits
    }

    func pump() {
        guard let pending, let connection else { return }
        do {
            try checkDeadline(pending)
            while let packet = pending.sender.take() {
                credits = pending.sender.credits
                sent.append(packet) // Acceptance into this model is M0's NCI submission boundary.
                try checkDeadline(pending)
                guard let apdu = try pending.request.accept(packet) else { continue }
                let reply = try backend.exchange(apdu, deadline: pending.deadline)
                let frames = try VPhoneNFCCodec.packets(reply, cid: connection.cid, pipe: connection.pipe, mps: connection.mps)
                for frame in frames { try receiveResponse(frame, generation: pending.generation) }
                break
            }
        } catch { fail(error as? VPhoneNFCError ?? .backend(String(describing: error))) }
    }

    func receiveResponse(_ packet: [UInt8], generation incoming: UInt64) throws {
        guard incoming == generation else { ignoredOldResponses += 1; return }
        guard let pending, pending.generation == incoming else { return }
        try checkDeadline(pending)
        received.append(packet)
        guard let reply = try pending.response.accept(packet) else { return }
        guard reply.count >= 2 else { throw VPhoneNFCError.invalidFrame }
        guard reply.count <= pending.capacity else { throw VPhoneNFCError.capacity }
        finish(.success(reply))
    }

    func pollDeadline() {
        guard let pending else { return }
        do { try checkDeadline(pending) } catch { fail(.timeout) }
    }

    func cancel() { if pending != nil { fail(.cancelled) } }
    func close() { if pending != nil { fail(.disconnected) } else { invalidate() } }

    private func checkDeadline(_ pending: Pending) throws {
        guard VPhoneNFCBackend.now < pending.deadline else { throw VPhoneNFCError.timeout }
    }

    private func fail(_ error: VPhoneNFCError) {
        // Revoke the ID-less stream before exposing failure or permitting a new request.
        let callback = pending?.completion
        if pending != nil { completions += 1 }
        pending = nil
        invalidate()
        callback?(.failure(error))
    }

    private func finish(_ result: Result<[UInt8], VPhoneNFCError>) {
        guard let pending else { return }
        self.pending = nil
        completions += 1
        pending.completion(result)
    }

    private func invalidate() {
        backend.stop()
        connection = nil; credits = 0; mode = .off
        generation += 1
    }
}
#endif
