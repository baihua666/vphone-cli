import Foundation

public struct VPhoneInstalledApplication: Sendable {
    public let version: String?
    public let build: String?

    public init(version: String?, build: String?) {
        self.version = version
        self.build = build
    }

    public static func parse(_ result: [String: Any]) throws -> [String: Self] {
        guard let apps = result["apps"] as? [[String: Any]] else { throw fail("客体未返回应用列表") }
        var installed: [String: Self] = [:]
        for app in apps {
            guard let id = app["bundle_id"] as? String, !id.isEmpty else { throw fail("客体应用列表缺少 Bundle ID，请重试读取") }
            installed[id] = Self(version: app["version"] as? String, build: app["build"] as? String)
        }
        return installed
    }

    public enum Comparison: Equatable, Sendable {
        case current, upgrade, guestNewer, unknown
    }

    /// Relative to this local IPA, never a claim about the latest store release.
    public func compare(localVersion: String, localBuild: String?) -> Comparison {
        guard let version, let order = Self.compareNumbers(localVersion, version) else { return .unknown }
        if order == .orderedDescending { return .upgrade }
        if order == .orderedAscending { return .guestNewer }
        guard let build, let localBuild, let buildOrder = Self.compareNumbers(localBuild, build) else { return .unknown }
        switch buildOrder {
        case .orderedAscending: return .guestNewer
        case .orderedDescending: return .upgrade
        case .orderedSame: return .current
        }
    }

    // Arbitrarily large numeric components; 1.10 > 1.9, 1.0 == 1.0.0.
    // Unknown/prerelease strings must not be guessed to be newer or current.
    static func compareNumbers(_ left: String, _ right: String) -> ComparisonResult? {
        func parts(_ value: String) -> [String]? {
            guard value.range(of: "^[0-9]+(\\.[0-9]+)*$", options: .regularExpression) != nil else { return nil }
            return value.split(separator: ".").map { let trimmed = $0.drop(while: { $0 == "0" }); return trimmed.isEmpty ? "0" : String(trimmed) }
        }
        guard let lhs = parts(left), let rhs = parts(right) else { return nil }
        for index in 0..<max(lhs.count, rhs.count) {
            let a = index < lhs.count ? lhs[index] : "0", b = index < rhs.count ? rhs[index] : "0"
            if a.count != b.count { return a.count < b.count ? .orderedAscending : .orderedDescending }
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
