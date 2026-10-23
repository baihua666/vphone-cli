import Foundation

/// FLYWHEEL policy only. The host supplies the selected machine's existing operations.
public enum VPhoneFlywheelWebPage {
    public static let urlPreferenceKey = "flywheel.businessWebURL"
    public static let includeIPPreferenceKey = "flywheel.businessWebIncludeIP"
    public static let safariBundleID = "com.apple.mobilesafari"

    public struct Route: Equatable, Sendable {
        public let identity: String
        public let endpoint: String

        public init(identity: String, endpoint: String) {
            self.identity = identity
            self.endpoint = endpoint
        }

        public func validate() throws {
            guard let url = URLComponents(string: "https://" + endpoint),
                  ["gate.decodo.com", "isp.decodo.com"].contains(url.host?.lowercased() ?? ""),
                  let port = url.port, (1...65535).contains(port),
                  url.user == nil, url.password == nil, url.path.isEmpty,
                  url.query == nil, url.fragment == nil else {
                throw VPhoneFlywheelError("当前实例未使用可确认的 DECODO 出口，请先在代理出口中配置并应用。")
            }
        }
    }

    public static func configuredURL(_ input: String) throws -> URLComponents {
        guard let url = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.url != nil else {
            throw VPhoneFlywheelError("请配置有效的 HTTP 或 HTTPS 业务网页地址，不包含账号密码。")
        }
        let hostName = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard hostName != "feishu.cn", !hostName.hasSuffix(".feishu.cn") else {
            throw VPhoneFlywheelError("禁止打开飞书网页，请配置 FLYWHEEL 业务地址。")
        }
        return url
    }

    public static func url(_ input: String, ip: String?, parameters: [VPhoneFlywheelURLParameter] = []) throws -> String {
        var components = try configuredURL(input)
        try VPhoneFlywheelURLParameter.validate(parameters)
        let managed = Set(parameters.map(\.key).filter { !$0.isEmpty }).union(["ip"])
        var items = components.queryItems ?? []
        items.removeAll { managed.contains($0.name) }
        components.queryItems = items.isEmpty ? nil : items
        var extra = URLComponents()
        var additions: [URLQueryItem] = []
        if let ip {
            try validateIP(ip)
            additions.append(URLQueryItem(name: "ip", value: ip))
        }
        additions += parameters.filter { $0.isEnabled && !$0.key.isEmpty }.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        if !additions.isEmpty {
            extra.queryItems = additions
            // A literal '+' must survive servers that decode queries as form data.
            let encoded = extra.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            components.percentEncodedQuery = [components.percentEncodedQuery, encoded].compactMap { $0 }.joined(separator: "&")
        }
        guard let result = components.url?.absoluteString else {
            throw VPhoneFlywheelError("无法生成业务网页地址。")
        }
        return result
    }

    public static func validateIP(_ ip: String) throws {
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ part in
            !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) } && UInt8(part) != nil
        }) else { throw VPhoneFlywheelError("Guest 未返回有效的公网 IPv4，出口检查未通过。") }
    }

    @MainActor
    @discardableResult
    public static func open(
        _ input: String,
        includeIP: Bool = true,
        parameters: [VPhoneFlywheelURLParameter] = [],
        route: () async throws -> Route,
        rpc: (String, [String: Any], Int) async throws -> [String: Any],
        onProgress: (String) -> Void = { _ in }
    ) async throws -> String {
        _ = try url(input, ip: nil, parameters: parameters)
        let ip = try await measure(route: route, rpc: rpc, onProgress: onProgress)
        let target = try url(input, ip: includeIP ? ip : nil, parameters: parameters)
        onProgress("正在目标虚拟机的 Safari 中打开网页…")
        let opened = try await rpc("apps.open_url", ["url": target, "bundle_id": safariBundleID], 30)
        guard opened["url"] as? String == target, opened["bundle_id"] as? String == safariBundleID else {
            throw VPhoneFlywheelError("核心未确认 Safari 打开结果，请检查该实例的 guest 能力。")
        }
        return ip
    }

    @MainActor
    public static func measure(
        route: () async throws -> Route,
        rpc: (String, [String: Any], Int) async throws -> [String: Any],
        onProgress: (String) -> Void = { _ in }
    ) async throws -> String {
        try Task.checkCancellation()
        let before = try await route()
        try before.validate()
        onProgress("正在从目标 guest 检测 DECODO 出口 IP…")
        let egress = try await rpc("network.egress", [:], 30)
        guard egress["origin"] as? String == "guest", let ip = egress["ip"] as? String else {
            throw VPhoneFlywheelError("未取得目标 guest 的出口 IP，出口检查未通过。")
        }
        try validateIP(ip)
        try Task.checkCancellation()
        guard try await route() == before else {
            throw VPhoneFlywheelError("检测期间实例出口已改变，请重新打开业务网页。")
        }
        try Task.checkCancellation()
        return ip
    }
}
