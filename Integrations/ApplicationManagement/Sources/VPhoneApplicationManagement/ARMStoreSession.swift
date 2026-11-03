import Foundation

public struct ARMStoreLoginRequired: LocalizedError {
    public init() {}
    public var errorDescription: String? { "下载权限验证失败，请重试下载。" }
}

public enum ARMStoreSession {
    public static func cookieHeader(_ cookies: [HTTPCookie], for url: URL, now: Date = Date()) -> String {
        guard url.scheme == "https", url.host == "armconverter.com" else { return "" }
        let matches = cookies.filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            let path = url.path.isEmpty ? "/" : url.path
            let pathMatches = path == cookie.path || (path.hasPrefix(cookie.path) &&
                (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).hasPrefix("/")))
            return domain == "armconverter.com" && pathMatches &&
                (cookie.expiresDate.map { $0 > now } ?? true)
        }.sorted { $0.path.count > $1.path.count }
        return matches.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    public static func allowsNavigation(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "armconverter.com" || host == "iosgods.com" || host.hasSuffix(".iosgods.com") || host == "challenges.cloudflare.com"
    }
}
