#if VPHONE_EXPERIMENTAL_HOST_CAMERA
import AVFoundation
import CoreVideo
import Foundation

@main
struct HostCameraTests {
    static func main() throws {
        try authorization()
        boundedFrames()
        staleCaptureCannotReplaceSelection()
        instanceIsolation()
        try rendering()
        print("PASS: authorization, bounded frames, cancellation, stale frames, instance isolation, BGRA and letterbox")
    }

    static func expectError(_ expected: VPhoneHostCameraError, _ operation: () throws -> Void) {
        do {
            try operation()
            fatalError("Expected \(expected)")
        } catch let error as VPhoneHostCameraError {
            precondition(error == expected)
        } catch {
            fatalError("Unexpected error: \(error)")
        }
    }

    static func authorization() throws {
        let authorized = try VPhoneHostCameraAuthorization.validate(.authorized, usageDescription: nil)
        let undetermined = try VPhoneHostCameraAuthorization.validate(.notDetermined, usageDescription: "Use selected camera")
        precondition(!authorized && undetermined)
        expectError(.permissionDenied) { _ = try VPhoneHostCameraAuthorization.validate(.denied, usageDescription: "Camera") }
        expectError(.permissionRestricted) { _ = try VPhoneHostCameraAuthorization.validate(.restricted, usageDescription: "Camera") }
        for missing in [nil, "", " \n "] as [String?] {
            expectError(.missingUsageDescription) {
                _ = try VPhoneHostCameraAuthorization.validate(.notDetermined, usageDescription: missing)
            }
        }
    }

    static func frame(_ timestamp: UInt64, value: UInt8 = 1) -> VPhoneHostCameraFrame {
        VPhoneHostCameraFrame(width: 1, height: 1, bytesPerRow: 4, timestampNS: timestamp,
                             pixels: Data([value, 0, 0, 255]))
    }

    static func boundedFrames() {
        let frames = VPhoneHostCameraFrames()
        precondition(frames.latest(nowNS: 10) == nil)
        let token = frames.begin()
        for i in 1...1000 { frames.publish(frame(UInt64(i)), generation: token) }
        precondition(frames.latest(nowNS: 1000)?.timestampNS == 1000)
        precondition(frames.latest(nowNS: 999) == nil, "Future frame must not underflow timestamp subtraction")
        precondition(frames.latest(nowNS: 500_001_000) != nil)
        precondition(frames.latest(nowNS: 500_001_001) == nil, "Disconnected cameras must not keep displaying a stale frame")
        frames.invalidate()
        precondition(frames.invalidate(generation: token) == nil, "An already stopped session must reject late errors")
        frames.publish(frame(1001), generation: token)
        precondition(frames.latest(nowNS: 1001) == nil, "Stop must clear and reject late callbacks")
    }

    static func staleCaptureCannotReplaceSelection() {
        let frames = VPhoneHostCameraFrames()
        let old = frames.begin()
        frames.publish(frame(10), generation: old)
        let current = frames.begin()
        precondition(frames.latest(nowNS: 10) == nil, "Selection change must clear the previous camera frame")
        frames.publish(frame(20, value: 2), generation: current)
        frames.publish(frame(30, value: 3), generation: old)
        precondition(frames.invalidate(generation: old) == nil, "Old permission/error completion must not stop the new selection")
        precondition(frames.isCurrent(current))
        precondition(frames.latest(nowNS: 30)?.pixels.first == 2)
    }

    static func instanceIsolation() {
        let first = VPhoneHostCameraFrames(), second = VPhoneHostCameraFrames()
        let a = first.begin(), b = second.begin()
        first.publish(frame(10, value: 7), generation: a)
        second.publish(frame(10, value: 9), generation: b)
        first.invalidate()
        precondition(first.latest(nowNS: 10) == nil)
        precondition(second.latest(nowNS: 10)?.pixels.first == 9)
    }

    static func pixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                       [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw VPhoneHostCameraError.startFailed }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
                bytes[index] = 0
                bytes[index + 1] = 0
                bytes[index + 2] = 255
                bytes[index + 3] = 255
            }
        }
        return buffer
    }

    static func rendering() throws {
        let renderer = VPhoneHostCameraRenderer(width: 10, height: 6)
        for (w, h, blackX, blackY) in [(2, 4, 0, 3), (8, 2, 5, 0)] {
            let buffer = try pixelBuffer(width: w, height: h)
            guard let result = renderer.render(buffer, timestampNS: 123) else { fatalError("No rendered frame") }
            precondition(result.width == 10 && result.height == 6)
            precondition(result.bytesPerRow == 48 && result.pixels.count == 48 * 6)
            precondition(result.timestampNS == 123)
            let center = 3 * result.bytesPerRow + 5 * 4
            precondition(result.pixels[center + 2] > 240, "Center must remain red in BGRA order")
            precondition(result.pixels[center] < 10 && result.pixels[center + 1] < 10)
            let border = blackY * result.bytesPerRow + blackX * 4
            precondition(result.pixels[border + 2] < 10, "Aspect fit must produce black borders")
            precondition(result.pixels[border + 3] == 255, "Black borders must be opaque")
        }
        let output = VPhoneHostCameraRenderer()
        precondition(output.width == 1280 && output.height == 720 && output.bytesPerRow == 5120)
        let asymmetric = try pixelBuffer(width: 4, height: 4)
        CVPixelBufferLockBaseAddress(asymmetric, [])
        let bottom = CVPixelBufferGetBaseAddress(asymmetric)!.advanced(by: 3 * CVPixelBufferGetBytesPerRow(asymmetric))
            .assumingMemoryBound(to: UInt8.self)
        for x in 0..<4 {
            bottom[x * 4] = 255
            bottom[x * 4 + 2] = 0
        }
        CVPixelBufferUnlockBaseAddress(asymmetric, [])
        let oriented = VPhoneHostCameraRenderer(width: 4, height: 4).render(asymmetric, timestampNS: 456)!
        precondition(oriented.pixels[2] > 240 && oriented.pixels[0] < 10, "Top row must stay red")
        precondition(oriented.pixels[3 * oriented.bytesPerRow] > 240, "Bottom row must stay blue")
    }
}
#endif
