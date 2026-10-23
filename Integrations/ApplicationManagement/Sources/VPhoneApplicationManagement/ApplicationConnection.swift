import Foundation

/// Adapter for the existing --api-listen console contract, not a new Core API.
public struct VPhoneApplicationConnection: Sendable {
    public let baseURL: URL
    private let token: String

    public init(log: String) throws {
        let lines = log.split(separator: "\n").map(String.init)
        let prefix = "[api] HTTP/WebSocket API: "
        guard let index = lines.lastIndex(where: { $0.hasPrefix(prefix) }),
              let components = URLComponents(string: String(lines[index].dropFirst(prefix.count))),
              components.scheme == "http", components.host == "127.0.0.1",
              let port = components.port, (1...65535).contains(port),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              let url = components.url,
              let tokenLine = lines[index...].first(where: { $0.hasPrefix("[api] token: ") }) else {
            throw fail("此运行会话未启用应用上传接口，请从新版 Launchpad 重新启动该实例。无需更换 Core。")
        }
        let token = String(tokenLine.dropFirst("[api] token: ".count))
        guard token.range(of: "^[A-Za-z0-9._~-]{16,256}$", options: .regularExpression) != nil else {
            throw fail("应用上传会话无效，请重新启动该实例。")
        }
        baseURL = url
        self.token = token
    }

    public func upload(_ local: URL, to path: String) async throws {
        guard path.hasPrefix("/"), !path.contains("\0") else { throw fail("无效客体路径") }
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/files/content"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "path", value: path), URLQueryItem(name: "mode", value: "644")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PUT"
        request.timeoutInterval = 660
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 660
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.upload(for: request, fromFile: local)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["error"] == nil, object["result"] != nil else {
            throw fail("目标实例拒绝上传，请检查运行状态与连接。")
        }
    }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
