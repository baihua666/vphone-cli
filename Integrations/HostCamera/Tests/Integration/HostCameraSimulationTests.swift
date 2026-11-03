#if VPHONE_EXPERIMENTAL_HOST_CAMERA
import CoreVideo
import Foundation

/// Software fixture only. It does not emulate a USB controller or change product device discovery.
@MainActor
enum HostCameraSimulationTests {
    static func run() async throws {
        let backend = DeferredCameraInput()
        var events: [VPhoneHostCameraProducer.State] = []
        let source = VPhoneHostCameraProducer(deviceID: "software-fixture", capture: backend) { events.append($0) }
        defer { source.stop() }
        source.start()
        try await ProducerLifecycleTests.eventually { backend.pending == 1 }
        backend.complete()
        try await ProducerLifecycleTests.eventually { events.last == .running }

        var optionalBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 16, 9, kCVPixelFormatType_32BGRA,
                                        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &optionalBuffer)
        guard status == kCVReturnSuccess, let buffer = optionalBuffer else { throw VPhoneHostCameraError.startFailed }
        let renderer = VPhoneHostCameraRenderer()
        let token = backend.frames.begin()
        var previous = Data()
        var last: VPhoneHostCameraFrame?
        for index in 0..<60 {
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            for y in 0..<9 {
                for x in 0..<16 {
                    let offset = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
                    base[offset] = UInt8(index * 4)
                    base[offset + 1] = UInt8(x * 15)
                    base[offset + 2] = UInt8(y * 28)
                    base[offset + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard let frame = renderer.render(buffer, timestampNS: DispatchTime.now().uptimeNanoseconds) else {
                fatalError("Software fixture did not render")
            }
            backend.frames.publish(frame, generation: token)
            guard let delivered = source.nextFrame() else { fatalError("Fresh simulated frame was not delivered") }
            precondition(delivered.width == 1280 && delivered.height == 720 && delivered.bytesPerRow == 5120)
            precondition(delivered.pixels.count == 3_686_400 && delivered.pixels == frame.pixels)
            precondition(delivered.pixels != previous, "Consecutive fixture frames must change")
            previous = delivered.pixels
            last = frame
        }

        backend.failRuntime()
        try await ProducerLifecycleTests.eventually { events.last == .failed("Disconnected") }
        precondition(source.nextFrame() == nil, "Disconnect must withdraw the last frame")
        source.start()
        try await ProducerLifecycleTests.eventually { backend.pending == 1 }
        backend.complete()
        try await ProducerLifecycleTests.eventually { events.last == .running }
        let reconnected = backend.frames.begin()
        backend.frames.publish(last!, generation: token)
        precondition(source.nextFrame() == nil, "Old device frames must not leak across reconnection")
        let fresh = renderer.render(buffer, timestampNS: DispatchTime.now().uptimeNanoseconds)!
        backend.frames.publish(fresh, generation: reconnected)
        precondition(source.nextFrame()?.pixels == fresh.pixels)
        source.stop()
        precondition(source.nextFrame() == nil)

        source.start()
        try await ProducerLifecycleTests.eventually { backend.pending == 1 }
        backend.complete(.permissionDenied)
        try await ProducerLifecycleTests.eventually {
            events.last == .failed(VPhoneHostCameraError.permissionDenied.localizedDescription)
        }
        precondition(source.nextFrame() == nil)
        print("PASS: software camera fixture, 60 changing 720p BGRA frames, unplug/reconnect, stale withdrawal and permission denial (not physical USB)")
    }
}
#endif
