#if VPHONE_EXPERIMENTAL_HOST_CAMERA
import Foundation

/// The only adapter between independent capture and the existing VM frame protocol.
/// Sendability: lifecycle stays on MainActor; frame reads use the capture input's locked slot.
final class VPhoneHostCameraProducer: VPhoneFrameProducer, @unchecked Sendable {
    enum State: Equatable { case starting, running, stopped, failed(String) }

    let deviceID: String
    private let capture: any VPhoneHostCameraInput
    @MainActor private var task: Task<Void, Never>?
    @MainActor private var generation: UInt64 = 0
    private let onState: @MainActor @Sendable (State) -> Void

    init(deviceID: String, capture: any VPhoneHostCameraInput = VPhoneHostCameraCapture(),
         onState: @escaping @MainActor @Sendable (State) -> Void) {
        self.deviceID = deviceID
        self.onState = onState
        self.capture = capture
    }

    @MainActor func start() {
        guard task == nil else { return }
        generation &+= 1
        let token = generation
        onState(.starting)
        guard generation == token else { return }
        task = Task { [weak self, capture, deviceID] in
            guard !Task.isCancelled, self?.generation == token else { return }
            do {
                try await capture.start(deviceID: deviceID) { [weak self] message in
                    Task { @MainActor in
                        guard let self, self.generation == token, self.task != nil else { return }
                        self.task = nil
                        self.onState(.failed(message))
                    }
                }
                guard let self, generation == token, !Task.isCancelled else { return }
                onState(.running)
            } catch {
                guard let self, generation == token, !Task.isCancelled else { return }
                task = nil
                onState(.failed(error.localizedDescription))
            }
        }
    }

    @MainActor func stop() {
        generation &+= 1
        task?.cancel()
        task = nil
        capture.stop()
        onState(.stopped)
    }

    func nextFrame() -> VPhoneCameraFrame? {
        guard let frame = capture.frames.latest() else { return nil }
        return VPhoneCameraFrame(width: frame.width, height: frame.height, bytesPerRow: frame.bytesPerRow,
                                 timestampNS: frame.timestampNS, pixels: frame.pixels)
    }

    deinit { capture.stop() }
}
#endif
