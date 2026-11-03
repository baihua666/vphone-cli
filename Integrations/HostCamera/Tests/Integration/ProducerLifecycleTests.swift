#if VPHONE_EXPERIMENTAL_HOST_CAMERA
import Foundation

/// Delayed permission/session completions without opening hardware. Production always uses AVFoundation.
final class DeferredCameraInput: VPhoneHostCameraInput, @unchecked Sendable {
    let frames = VPhoneHostCameraFrames()
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, any Error>] = []
    private var failure: (@Sendable (String) -> Void)?
    private var starts = 0
    private var stops = 0
    var pending: Int { lock.withLock { continuations.count } }
    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }

    func start(deviceID: String, onFailure: @escaping @Sendable (String) -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                starts += 1
                failure = onFailure
                continuations.append(continuation)
            }
        }
    }

    func stop() {
        lock.withLock { stops += 1 }
        frames.invalidate()
    }

    func complete(_ error: VPhoneHostCameraError? = nil) {
        let continuation = lock.withLock { continuations.removeFirst() }
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }

    func failRuntime() {
        frames.invalidate()
        let callback = lock.withLock { failure }
        callback?("Disconnected")
    }
}

@MainActor
enum ProducerLifecycleTests {
    static func eventually(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !predicate() {
            precondition(ContinuousClock.now < deadline, "Timed out waiting for capture lifecycle")
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    static func run() async throws {
        let immediate = DeferredCameraInput()
        let cancelled = VPhoneHostCameraProducer(deviceID: "test", capture: immediate) { _ in }
        cancelled.start()
        cancelled.stop()
        try await Task.sleep(for: .milliseconds(10))
        precondition(immediate.startCount == 0, "Immediate stop must prevent a permission/session request")

        let input = DeferredCameraInput()
        var events: [VPhoneHostCameraProducer.State] = []
        let producer = VPhoneHostCameraProducer(deviceID: "test", capture: input) { events.append($0) }
        producer.start()
        producer.start()
        try await eventually { input.pending == 1 }
        precondition(input.startCount == 1, "Repeated start must not open a second session")
        producer.stop()
        producer.start()
        try await eventually { input.pending == 2 }
        input.complete()
        input.complete()
        try await eventually { events.last == .running }
        precondition(events.filter { $0 == .running }.count == 1, "Old completion must not report a new capture")
        let frame = VPhoneHostCameraFrame(width: 1, height: 1, bytesPerRow: 4,
                                         timestampNS: DispatchTime.now().uptimeNanoseconds, pixels: Data([0, 0, 255, 255]))
        let frameToken = input.frames.begin()
        input.frames.publish(frame, generation: frameToken)
        let adapted = producer.nextFrame()
        precondition(adapted?.width == 1 && adapted?.height == 1 && adapted?.bytesPerRow == 4)
        precondition(adapted?.pixels == frame.pixels && adapted?.timestampNS == frame.timestampNS)
        input.failRuntime()
        producer.stop()
        precondition(producer.nextFrame() == nil, "Stop must stop exposing captured frames")
        try await Task.sleep(for: .milliseconds(10))
        precondition(!events.contains(.failed("Disconnected")), "Queued runtime error must be ignored after stop")

        producer.start()
        try await eventually { input.pending == 1 }
        input.complete(.deviceUnavailable)
        try await eventually {
            if case .failed = events.last { return true }
            return false
        }
        producer.start()
        try await eventually { input.pending == 1 }
        input.complete()
        try await eventually { events.last == .running }
        producer.stop()
        precondition(input.stopCount >= 3)

        let releasedInput = DeferredCameraInput()
        var released: VPhoneHostCameraProducer? = VPhoneHostCameraProducer(deviceID: "test", capture: releasedInput) { _ in }
        precondition(released?.deviceID == "test")
        released = nil
        precondition(releasedInput.stopCount == 1, "Source release must stop capture")
        print("PASS: immediate cancellation, delayed completion, duplicate start, stale errors, failure retry and source release")
    }
}
#endif
