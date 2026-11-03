import Foundation

public struct ARMStoreAuthenticationTimeout: LocalizedError {
    public init() {}
    public var errorDescription: String? { "下载准备超时，请检查网络后重试。" }
}

/// Keeps the original download pending while the supplier completes authentication.
/// No download authorization or quota-consuming request is made here.
public enum ARMStoreAuthentication {
    @MainActor public static func ensureSession(
        timeout: Duration = .seconds(300), interval: Duration = .seconds(1),
        check: () async throws -> Bool, begin: () -> Void,
        cancelled: () -> Bool = { false }
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        func checkCancellation() throws {
            try Task.checkCancellation()
            if cancelled() { throw CancellationError() }
        }
        try checkCancellation()
        let restored = try await check()
        try checkCancellation()
        if restored { return }
        begin()
        while ContinuousClock.now < deadline {
            try checkCancellation()
            let ready = try await check()
            try checkCancellation()
            if ready { return }
            try await Task.sleep(for: min(interval, ContinuousClock.now.duration(to: deadline)))
        }
        throw ARMStoreAuthenticationTimeout()
    }
}
