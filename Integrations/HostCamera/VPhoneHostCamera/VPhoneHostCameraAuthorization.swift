#if VPHONE_EXPERIMENTAL_HOST_CAMERA
import AVFoundation
import Foundation

enum VPhoneHostCameraError: LocalizedError, Equatable {
    case permissionDenied, permissionRestricted, missingUsageDescription
    case deviceUnavailable, cannotAddInput, cannotAddOutput, startFailed, cancelled

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Camera access was denied. Allow camera access for the launching app in System Settings. Launchpad also needs a matching camera-enabled build and signature."
        case .permissionRestricted: "Camera access is restricted on this Mac."
        case .missingUsageDescription: "This build has no camera usage description. Rebuild the host camera integration before requesting access."
        case .deviceUnavailable: "The selected host camera is unavailable. Reconnect it and select it again."
        case .cannotAddInput: "The host camera cannot be added to the capture session."
        case .cannotAddOutput: "The host camera cannot provide BGRA frames."
        case .startFailed: "The host camera did not start. Check that it is connected and available."
        case .cancelled: "Host camera selection was cancelled."
        }
    }
}

enum VPhoneHostCameraAuthorization {
    static func validate(_ status: AVAuthorizationStatus, usageDescription: String?) throws -> Bool {
        switch status {
        case .authorized: return false
        case .denied: throw VPhoneHostCameraError.permissionDenied
        case .restricted: throw VPhoneHostCameraError.permissionRestricted
        case .notDetermined:
            guard let usageDescription, !usageDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VPhoneHostCameraError.missingUsageDescription
            }
            return true
        @unknown default: throw VPhoneHostCameraError.permissionRestricted
        }
    }

    /// Only call after the user selects a camera; enumeration and module loading never prompt.
    static func request() async throws {
        let shouldRequest = try validate(
            AVCaptureDevice.authorizationStatus(for: .video),
            usageDescription: Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String
        )
        if shouldRequest, !(await AVCaptureDevice.requestAccess(for: .video)) {
            throw VPhoneHostCameraError.permissionDenied
        }
    }
}
#endif
