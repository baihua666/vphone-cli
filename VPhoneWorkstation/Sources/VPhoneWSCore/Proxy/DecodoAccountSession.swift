import Foundation

public actor DecodoAccountSession {
    public static let shared = DecodoAccountSession()
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport
    private var pending: Task<Data, Error>?
    public init() { transport = Self.send }
    init(transport: @escaping Transport) { self.transport = transport }

    public func subscriptions() async throws -> Data {
        if let pending { return try await pending.value }
        let task = Task {
            let loaded = try DecodoAccount.load()
            var account = loaded.account
            let result: Result<Data, Error>
            do { result = .success(try await self.authorizedSubscriptions(account: &account)) }
            catch { result = .failure(error) }
            // Do not overwrite settings edited while a request was in progress.
            let current = try DecodoAccount.load()
            guard current.path == loaded.path, current.account == loaded.account else {
                throw ProxyRouteError("账号设置已改变，请重新同步。")
            }
            if account != loaded.account { try account.save(path: loaded.path) }
            return try result.get()
        }
        pending = task
        defer { pending = nil }
        return try await task.value
    }

    func authorizedSubscriptions(account: inout DecodoAccount) async throws -> Data {
        if !account.accessToken.isEmpty {
            let response = try await call("/subscription-api/v1/subscriptions", account: account)
            if response.1.statusCode == 200 { return response.0 }
            guard response.1.statusCode == 401 else { throw failure(response.1.statusCode) }
        }
        if !account.refreshToken.isEmpty {
            let response = try await call("/api/v1/token/refresh", account: account, body: [:])
            if response.1.statusCode == 200 {
                update(&account, response: response)
                let retry = try await call("/subscription-api/v1/subscriptions", account: account)
                if retry.1.statusCode == 200 { return retry.0 }
                guard retry.1.statusCode == 401 else { throw failure(retry.1.statusCode) }
            } else if response.1.statusCode != 401 { throw failure(response.1.statusCode) }
        }
        guard !account.email.isEmpty, !account.password.isEmpty else {
            throw ProxyRouteError("请在 Decodo 账号设置填写网站登录邮箱和密码，或提供有效授权会话。代理用户名不能用于网页登录。")
        }
        let login = try await call("/api/v1/users/login/", account: DecodoAccount(),
                                   body: ["username": account.email, "email": account.email,
                                          "password": account.password, "type": "sp"])
        guard login.1.statusCode == 200 else { throw failure(login.1.statusCode) }
        update(&account, response: login)
        guard !account.accessToken.isEmpty else { throw ProxyRouteError("登录未返回会话，可能需要网页验证；请完成验证后填写授权会话。") }
        let response = try await call("/subscription-api/v1/subscriptions", account: account)
        guard response.1.statusCode == 200 else { throw failure(response.1.statusCode) }
        return response.0
    }
    private func call(_ path: String, account: DecodoAccount, body: [String: String]? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: "https://dashboard.decodo.cn" + path)!)
        let cookies = [("JWT-AUTH", account.accessToken), ("refresh_token", account.refreshToken)]
            .filter { !$0.1.isEmpty }
        guard cookies.allSatisfy({ $0.1.utf8.allSatisfy { $0 > 32 && $0 < 127 && $0 != 59 } }) else {
            throw ProxyRouteError("授权会话格式无效")
        }
        request.setValue(cookies.map { "\($0.0)=\($0.1)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        return try await transport(request)
    }
    private func update(_ account: inout DecodoAccount, response: (Data, HTTPURLResponse)) {
        let object = (try? JSONSerialization.jsonObject(with: response.0)) as? [String: Any]
        if let token = object?["token"] as? String { account.accessToken = token }
        if let token = object?["refresh_token"] as? String { account.refreshToken = token }
        let headers = response.1.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
        }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: response.1.url!) {
            if cookie.name == "JWT-AUTH" { account.accessToken = cookie.value }
            if cookie.name == "refresh_token" { account.refreshToken = cookie.value }
        }
    }
    private func failure(_ status: Int) -> ProxyRouteError {
        ProxyRouteError(status == 210 || status == 403
            ? "Decodo 要求二次验证或网页验证，请在官网完成；未绕过验证。"
            : "Decodo 授权请求失败（HTTP \(status)），请检查账号或会话；不会自动切换账号。")
    }
    private static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.timeoutIntervalForRequest = 25
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ProxyRouteError("Decodo 响应无效") }
        return (data, response)
    }
    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
    }
}
