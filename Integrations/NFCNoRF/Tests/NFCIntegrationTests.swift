#if VPHONE_EXPERIMENTAL_NFC_NO_RF
import Darwin
import Foundation

func testNFCIntegration(backend: VPhoneNFCBackend, checks: VPhoneNFCChecks) throws -> [[String: Any]] {
    let session = VPhoneNFCSession(backend: backend)
    defer { session.close() }
    var events: [[String: Any]] = []
    func reopen(credits: UInt8 = 1) throws {
        let atr = try session.open(cid: 3, pipe: 0x16, mps: 17, credits: credits)
        try checks.check(!atr.isEmpty && session.mode == .off, "real backend ATR barrier, software Off")
        try session.setMode(.apdu)
    }
    func finish(_ capture: VPhoneNFCResultCapture) throws {
        while session.isPending {
            session.pump()
            if session.isPending { try session.grant([0x60, 6, 3, 1, 3, 1]) }
        }
        try checks.check(capture.results.count == 1, "model callback exactly once")
    }
    func selected() throws {
        let capture = VPhoneNFCResultCapture()
        try session.begin(VPhoneNFCResearchProbe.select, completion: capture.receive)
        try finish(capture)
        try checks.check(capture.bytes == [0x90, 0], "SELECT after new backend/reset")
    }

    try checks.fails(.invalidState) { try session.setMode(.apdu) }
    try reopen(credits: 0)
    try session.setMode(.off)
    try checks.fails(.invalidState) { try session.begin(VPhoneNFCResearchProbe.select) { _ in } }
    try session.setMode(.apdu)
    let zero = VPhoneNFCResultCapture()
    try session.begin(VPhoneNFCResearchProbe.select, completion: zero.receive)
    try checks.fails(.busy) { try session.begin(VPhoneNFCResearchProbe.select) { _ in } }
    try checks.fails(.busy) { try session.setMode(.off) }
    session.pump()
    try checks.check(session.sent.isEmpty && zero.results.isEmpty, "zero credit submits nothing")
    try checks.fails(.invalidFrame) { try session.grant([0x60, 6, 3, 1, 4, 1]) }
    try session.grant([0x60, 6, 3, 1, 3, 0]); session.pump()
    try checks.check(session.sent.isEmpty && zero.results.isEmpty, "zero delta still paused")
    try session.grant([0x60, 6, 3, 1, 3, 1]); session.pump()
    try checks.check(zero.bytes == [0x90, 0] && zero.results.count == 1, "positive matching credit resumes real SELECT")
    session.pump(); session.pollDeadline()
    try checks.check(zero.results.count == 1, "completed request cannot finish twice")
    events.append(["name": "zero-credit-real-select", "response": "9000", "nci_tx": session.sent.count])

    for length in [248, 249, 255] {
        let nonce = (0..<length).map { UInt8($0 & 255) }
        let capture = VPhoneNFCResultCapture()
        try session.begin(VPhoneNFCResearchProbe.echo(nonce), completion: capture.receive)
        try finish(capture)
        try checks.check(capture.bytes == nonce + [0x90, 0], "real long echo \(length)")
        try checks.check(session.sent.count > 1 && session.received.count > 1, "both directions fragment by MPS")
        events.append(["name": "fragmented-real-echo", "nonce_bytes": length,
                       "nci_tx": session.sent.count, "nci_rx": session.received.count,
                       "response": VPhoneNFCResearchProbe.hex(capture.bytes!)])
    }

    let small = VPhoneNFCResultCapture()
    try session.begin(VPhoneNFCResearchProbe.select, capacity: 1, completion: small.receive)
    try finish(small)
    try checks.check(small.failure == .capacity && session.mode == .off && !backend.isConnected, "capacity failure revokes stream")
    try reopen(); try selected()

    let stoppedPID = backend.processIdentifier!
    try checks.check(kill(stoppedPID, SIGSTOP) == 0, "pause owned real Java backend")
    usleep(50_000)
    let oldGeneration = session.generation
    let timeout = VPhoneNFCResultCapture()
    let timeoutBegan = VPhoneNFCBackend.now
    try session.begin(VPhoneNFCResearchProbe.echo([1, 2, 3]), timeout: 0.15, completion: timeout.receive)
    try finish(timeout)
    let elapsed = VPhoneNFCBackend.now - timeoutBegan
    try checks.check(elapsed >= 0.14 && elapsed < 3, "monotonic backend deadline is bounded")
    try checks.check(timeout.failure == .timeout && !backend.isConnected && session.mode == .off, "real backend wait times out")
    try checks.check(session.generation > oldGeneration && timeout.results.count == 1, "timeout invalidates generation")
    events.append(["name": "paused-real-backend-timeout", "error": "timeout", "elapsed_seconds": elapsed,
                   "old_generation": oldGeneration])

    try reopen(credits: 0)
    let held = VPhoneNFCResultCapture()
    try session.begin(VPhoneNFCResearchProbe.select, completion: held.receive)
    let oldResponse = try VPhoneNFCCodec.packets([0x90, 0], cid: 3, pipe: 0x16, mps: 17)[0]
    try session.receiveResponse(oldResponse, generation: oldGeneration)
    try checks.check(held.results.isEmpty && session.ignoredOldResponses == 1, "late old generation cannot satisfy new request")
    try finish(held)
    try checks.check(held.bytes == [0x90, 0], "recovery requires fresh real SELECT")
    events.append(["name": "timeout-recovery-select", "generation": session.generation, "response": "9000"])

    let deadPID = backend.processIdentifier!
    try checks.check(kill(deadPID, SIGKILL) == 0, "terminate owned backend for EOF test")
    usleep(50_000)
    let disconnected = VPhoneNFCResultCapture()
    try session.begin(VPhoneNFCResearchProbe.echo([4, 5, 6]), completion: disconnected.receive)
    try finish(disconnected)
    try checks.check(disconnected.failure == .disconnected && !backend.isConnected, "backend EOF fails pending once")
    try reopen(); try selected()
    let nonce: [UInt8] = [0x65, 0x6f, 0x66, 0x2d, 0x72, 0x65, 0x63, 0x6f, 0x76, 0x65, 0x72]
    let recovered = VPhoneNFCResultCapture()
    try session.begin(VPhoneNFCResearchProbe.echo(nonce), completion: recovered.receive)
    try finish(recovered)
    try checks.check(recovered.bytes == nonce + [0x90, 0], "real echo after EOF recovery")
    events.append(["name": "disconnect-recovery-echo", "response": VPhoneNFCResearchProbe.hex(recovered.bytes!)])

    // No credit: no backend execution; cancel still revokes the entire ID-less session.
    let cancelled = VPhoneNFCResultCapture()
    try session.begin(VPhoneNFCResearchProbe.select, completion: cancelled.receive)
    session.cancel(); session.cancel(); session.pollDeadline()
    try checks.check(cancelled.failure == .cancelled && cancelled.results.count == 1 && !backend.isConnected,
                     "cancel callback once and owned stream closed")
    try reopen(credits: 0)
    let creditTimeout = VPhoneNFCResultCapture()
    try session.begin(VPhoneNFCResearchProbe.select, timeout: 0.01, completion: creditTimeout.receive)
    session.pump(); usleep(20_000); session.pollDeadline()
    try checks.check(creditTimeout.failure == .timeout && session.sent.isEmpty && !backend.isConnected,
                     "credit wait deadline fails without any submission")
    events.append(["name": "credit-wait-timeout", "error": "timeout", "nci_tx": 0])
    return events
}
#endif
