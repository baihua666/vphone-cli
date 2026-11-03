#if VPHONE_EXPERIMENTAL_HOST_CAMERA
import CoreImage
import CoreVideo
import Foundation

struct VPhoneHostCameraFrame: Sendable {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let timestampNS: UInt64
    let pixels: Data
}

/// One frame, not a queue: slow VM consumers cannot accumulate capture buffers.
final class VPhoneHostCameraFrames: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var active = false
    private var frame: VPhoneHostCameraFrame?

    @discardableResult
    func begin() -> UInt64 {
        lock.withLock {
            generation &+= 1
            active = true
            frame = nil
            return generation
        }
    }

    @discardableResult
    func invalidate(generation token: UInt64? = nil) -> UInt64? {
        lock.withLock {
            guard token == nil || (active && token == generation) else { return nil }
            active = false
            frame = nil
            return generation
        }
    }

    func isCurrent(_ token: UInt64) -> Bool {
        lock.withLock { active && generation == token }
    }

    func publish(_ value: VPhoneHostCameraFrame, generation token: UInt64) {
        lock.withLock {
            guard active, generation == token else { return }
            frame = value
        }
    }

    func latest(nowNS: UInt64 = DispatchTime.now().uptimeNanoseconds) -> VPhoneHostCameraFrame? {
        lock.withLock {
            guard active, let frame, nowNS >= frame.timestampNS,
                  nowNS - frame.timestampNS <= 500_000_000 else { return nil }
            return frame
        }
    }
}

/// Used only on the capture queue. Preserve aspect ratio and emit the existing BGRA wire format.
final class VPhoneHostCameraRenderer {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    init(width: Int = 1280, height: Int = 720) {
        precondition(width > 0 && width <= 4096 && height > 0 && height <= 4096)
        self.width = width
        self.height = height
        bytesPerRow = (width * 4 + 15) & ~15
    }

    func render(_ buffer: CVPixelBuffer, timestampNS: UInt64) -> VPhoneHostCameraFrame? {
        guard CVPixelBufferGetWidth(buffer) > 0, CVPixelBufferGetHeight(buffer) > 0 else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)
        let scale = min(CGFloat(width) / image.extent.width, CGFloat(height) / image.extent.height)
        let transform = CGAffineTransform(scaleX: scale, y: scale).concatenating(
            CGAffineTransform(translationX: (CGFloat(width) - image.extent.width * scale) / 2,
                              y: (CGFloat(height) - image.extent.height * scale) / 2)
        )
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let result = image.transformed(by: transform).composited(over: CIImage(color: .black)).cropped(to: bounds)
        var pixels = Data(count: bytesPerRow * height)
        pixels.withUnsafeMutableBytes { bytes in
            context.render(result, toBitmap: bytes.baseAddress!, rowBytes: bytesPerRow,
                           bounds: bounds, format: .BGRA8, colorSpace: colorSpace)
        }
        return VPhoneHostCameraFrame(width: width, height: height, bytesPerRow: bytesPerRow,
                                    timestampNS: timestampNS, pixels: pixels)
    }
}
#endif
