import Foundation

#if VPHONE_CUSTOM_NATIVE_PROXY_WORKFLOW
/// A tested endpoint belongs to one form selection and one pinned machine context.
struct NativeDecodoSelection: Equatable {
    let credentialsPath: String
    let isp: Bool
    let city: String
    let zip: String
    let interface: String
    let device: String
    let target: DecodoLocation?
}

struct NativeDecodoCandidate {
    let selection: NativeDecodoSelection
    let credentials: NativeDecodoService.Credentials
    let config: NativeDecodoConfiguration
    let directory: URL
    let executable: URL
    let location: IPLocation

    func validate(selection: NativeDecodoSelection, credentials: NativeDecodoService.Credentials,
                  context: VMCommandContext, occupied: Set<Int>) throws {
        guard self.selection == selection, self.credentials == credentials,
              directory == context.directory, executable == context.executable else {
            throw ProxyRouteError("地区、账号或实例绑定已改变，请重新检测后保存。")
        }
        guard config.host != "isp.decodo.com" || !occupied.contains(config.port) else {
            throw ProxyRouteError("检测的入口已被使用，请重新检测后保存。")
        }
    }
}

#endif

/// Existing network operations injected only to exercise the complete controller without a live account.
struct NativeDecodoProbe: Sendable {
    var validate: @Sendable (String, String) throws -> Void = { try NativeDecodoService.validateDevice($0, type: $1) }
    var resolve: @Sendable (String, String) async throws -> String = { try await NativeDecodoService.resolve(host: $0, device: $1) }
    var probe: @Sendable (NativeDecodoConfiguration, String) async throws -> IPLocation = { try await NativeDecodoService.probe($0, device: $1) }
}
