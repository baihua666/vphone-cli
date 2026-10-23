import Foundation

/// A business preparation step, independent of VM creation and firmware installation.
public enum VPhoneFlywheelNetworkPreparation {
    @MainActor
    public static func verify(
        check: () async throws -> String,
        wait: () async throws -> Void = { try await Task.sleep(for: .seconds(2)) }
    ) async throws -> String {
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do { return try await check() }
            catch is CancellationError { throw CancellationError() }
            catch {
                if attempt == 2 { throw error }
                try await wait()
            }
        }
        throw VPhoneFlywheelError("Guest 出口检查未完成。")
    }

    @MainActor
    public static func run(
        isTunnel: Bool, isRunning: Bool,
        stop: () async throws -> Void,
        setTunnel: () async throws -> Void,
        start: () async throws -> Void,
        connectDecodo: () async throws -> Void,
        verify: () async throws -> String,
        onProgress: (String) -> Void = { _ in }
    ) async throws -> String {
        try Task.checkCancellation()
        if !isTunnel {
            if isRunning {
                onProgress("正在正常关闭目标实例，以应用 tunnel 网络…")
                try await stop()
            }
            try Task.checkCancellation()
            onProgress("正在配置目标实例的 tunnel 网络…")
            try await setTunnel()
        }
        if !isRunning || !isTunnel {
            try Task.checkCancellation()
            onProgress("正在启动目标实例并等待 guest…")
            try await start()
        }
        try Task.checkCancellation()
        onProgress("正在准备此实例的 DECODO 出口…")
        try await connectDecodo()
        try Task.checkCancellation()
        onProgress("正在从 guest 验证实际公网 IP…")
        return try await verify()
    }
}
