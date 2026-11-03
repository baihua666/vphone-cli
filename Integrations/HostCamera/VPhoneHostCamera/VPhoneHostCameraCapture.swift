#if VPHONE_EXPERIMENTAL_HOST_CAMERA
@preconcurrency import AVFoundation
import Foundation

struct VPhoneHostCameraDevice: Sendable {
    let id: String
    let name: String
}

protocol VPhoneHostCameraInput: AnyObject, Sendable {
    var frames: VPhoneHostCameraFrames { get }
    func start(deviceID: String, onFailure: @escaping @Sendable (String) -> Void) async throws
    func stop()
}

/// AVFoundation state and callbacks stay on one queue; only the bounded frame slot crosses queues.
final class VPhoneHostCameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, VPhoneHostCameraInput, @unchecked Sendable {
    let frames = VPhoneHostCameraFrames()
    private let queue = DispatchQueue(label: "com.vphone.host-camera.capture", qos: .userInitiated)
    private let renderer = VPhoneHostCameraRenderer()
    private var session: AVCaptureSession?
    private var activeGeneration: UInt64 = 0
    private var observers: [NSObjectProtocol] = []

    static func devices() -> [VPhoneHostCameraDevice] {
        discovery().devices.map { VPhoneHostCameraDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    private static func discovery() -> AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external],
                                         mediaType: .video, position: .unspecified)
    }

    func start(deviceID: String, onFailure: @escaping @Sendable (String) -> Void = { _ in }) async throws {
        try Task.checkCancellation()
        let token = frames.begin()
        do {
            try Task.checkCancellation()
            try await VPhoneHostCameraAuthorization.request()
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                queue.async {
                    do {
                        guard self.frames.isCurrent(token) else { throw VPhoneHostCameraError.cancelled }
                        self.stopSession()
                        try self.configure(deviceID: deviceID, token: token, onFailure: onFailure)
                        continuation.resume()
                    } catch {
                        if self.frames.invalidate(generation: token) != nil {
                            self.stopSession()
                        }
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            // A denied, older permission request must not invalidate a newer selection.
            stop(generation: token)
            throw error
        }
    }

    func stop() {
        stop(generation: nil)
    }

    private func stop(generation: UInt64?) {
        guard frames.invalidate(generation: generation) != nil else { return }
        queue.async {
            if !self.frames.isCurrent(self.activeGeneration) { self.stopSession() }
        }
    }

    private func configure(deviceID: String, token: UInt64, onFailure: @escaping @Sendable (String) -> Void) throws {
        guard let device = Self.discovery().devices.first(where: { $0.uniqueID == deviceID }),
              device.isConnected else { throw VPhoneHostCameraError.deviceUnavailable }
        let input = try AVCaptureDeviceInput(device: device)
        let capture = AVCaptureSession()
        capture.beginConfiguration()
        if capture.canSetSessionPreset(.hd1280x720) { capture.sessionPreset = .hd1280x720 }
        guard capture.canAddInput(input) else {
            capture.commitConfiguration()
            throw VPhoneHostCameraError.cannotAddInput
        }
        capture.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        guard capture.canAddOutput(output) else {
            capture.commitConfiguration()
            throw VPhoneHostCameraError.cannotAddOutput
        }
        capture.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
        capture.commitConfiguration()
        session = capture
        activeGeneration = token
        observe(AVCaptureSession.runtimeErrorNotification, object: capture, token: token, onFailure: onFailure)
        observe(AVCaptureSession.wasInterruptedNotification, object: capture, token: token, onFailure: onFailure)
        observe(AVCaptureDevice.wasDisconnectedNotification, object: device, token: token, onFailure: onFailure)
        capture.startRunning()
        guard capture.isRunning else { throw VPhoneHostCameraError.startFailed }
        guard frames.isCurrent(token) else {
            stopSession()
            throw VPhoneHostCameraError.cancelled
        }
    }

    private func observe(_ name: Notification.Name, object: AnyObject, token: UInt64,
                         onFailure: @escaping @Sendable (String) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                guard self.frames.invalidate(generation: token) != nil else { return }
                self.stopSession()
                onFailure("Host camera stopped or disconnected. Select the camera again to retry.")
            }
        })
    }

    private func stopSession() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        session?.stopRunning()
        session?.outputs.compactMap { $0 as? AVCaptureVideoDataOutput }.forEach {
            $0.setSampleBufferDelegate(nil, queue: nil)
        }
        session = nil
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard frames.isCurrent(activeGeneration), let buffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let frame = renderer.render(buffer, timestampNS: DispatchTime.now().uptimeNanoseconds) else { return }
        frames.publish(frame, generation: activeGeneration)
    }

    deinit {
        frames.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
        let capture = session
        queue.async {
            capture?.stopRunning()
            capture?.outputs.compactMap { $0 as? AVCaptureVideoDataOutput }.forEach {
                $0.setSampleBufferDelegate(nil, queue: nil)
            }
        }
    }
}
#endif
