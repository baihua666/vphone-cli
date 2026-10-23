import Foundation

public struct VPhoneApplicationInstallUnconfirmed: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

/// Launchpad owns the workflow. Transports are bound to one selected machine;
/// all operations below already exist in the installed Core/guest API.
@MainActor public enum VPhoneApplicationInstallation {
    public static func install(
        url: URL, bundleID: String,
        upload: (URL, String) async throws -> Void,
        send: ([String: Any], Int) async throws -> [String: Any]
    ) async throws -> Set<String> {
        func rpc(_ method: String, _ params: [String: Any] = [:], timeout: Int = 120) async throws -> [String: Any] {
            let reply = try await send(["t": "rpc", "method": method, "params": params], timeout)
            guard reply["ok"] as? Bool == true, let result = reply["result"] as? [String: Any] else {
                throw fail("客体操作失败：\(method)：\(reply["error"] as? String ?? "响应缺少 result")")
            }
            return result
        }
        _ = try await rpc("apps.list") // Fail before upload if this target is disconnected.
        try await Task.detached { try VPhoneApplicationLibrary.validate(url) }.value
        let directory = "/var/mobile/Documents/vphone-installs"
        let path = directory + "/" + UUID().uuidString + "." + url.pathExtension.lowercased()
        _ = try await rpc("files.mkdir", ["path": directory])
        do { try await upload(url, path) }
        catch {
            _ = try? await rpc("files.remove", ["path": path])
            throw fail("上传失败，未发起安装。\n\(error.localizedDescription)")
        }
        do { _ = try await rpc("apps.install", ["path": path, "registration": "User"], timeout: 660) }
        catch {
            // A timeout does not cancel guest installation. Keep its input intact.
            throw VPhoneApplicationInstallUnconfirmed(message: "安装失败或未确认完成：\(error.localizedDescription)\n请先刷新客体列表再决定是否重试。如发生超时或连接中断，客体操作不一定已取消。\n保留的临时包：\(path)")
        }
        _ = try? await rpc("files.remove", ["path": path])
        do {
            let result = try await rpc("apps.list")
            guard let apps = result["apps"] as? [[String: Any]] else { throw fail("安装后无法读取客体应用列表，请手动刷新。") }
            let installed = Set(apps.compactMap { $0["bundle_id"] as? String })
            guard installed.contains(bundleID) else { throw fail("安装返回成功，但客体列表未找到该应用。") }
            return installed
        } catch {
            throw VPhoneApplicationInstallUnconfirmed(message: "安装已返回成功，但读回未确认；请先刷新客体列表。\n\(error.localizedDescription)")
        }
    }
}
