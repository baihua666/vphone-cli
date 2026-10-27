import Foundation
import Security

/// App-side admission only; no helper protocol or installed daemon changes.
nonisolated struct VPhoneLaunchpadHelperCompatibility {
    // Build 15 supplies this app's XPC interface. Later builds must preserve it.
    // Raise this floor only for required helper features or security fixes,
    // independently of the main app's version and its bundled helper build.
    static let minimumVersion = "15"

    var bundledHelper = Bundle.main.bundleURL.appendingPathComponent(
        "Contents/Library/LaunchServices/\(VPhoneLaunchpadHelperIdentity.label)"
    )
    var installedHelper = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/\(VPhoneLaunchpadHelperIdentity.label)")
    var job = URL(fileURLWithPath: "/Library/LaunchDaemons/\(VPhoneLaunchpadHelperIdentity.label).plist")
    var requirement = (Bundle.main.object(forInfoDictionaryKey: "SMPrivilegedExecutables") as? [String: String])?[
        VPhoneLaunchpadHelperIdentity.label
    ]

    var isConfigured: Bool {
        guard let requirement else { return false }
        return !requirement.isEmpty && !requirement.contains("subject.OU] = \"\"")
    }

    var bundledVersion: String? { Self.version(at: bundledHelper) }

    static func isCompatible(_ version: String) -> Bool {
        guard let order = compare(version, minimumVersion) else { return false }
        return order != .orderedAscending
    }

    func requireUpgrade() throws {
        guard let bundledVersion, Self.isCompatible(bundledVersion) else {
            throw VPhoneLaunchpadError(String(localized: "This app does not contain a compatible helper. Update the app, then check again."))
        }
        if let installed = try installedVersion(), Self.compare(bundledVersion, installed) != .orderedDescending {
            throw VPhoneLaunchpadError(String(localized: "The installed helper is the same version or newer. It has not been replaced."))
        }
    }

    /// Validate the installed file before trusting its embedded version. XPC
    /// separately authenticates the running process with the same requirement.
    func installedVersion() throws -> String? {
        guard FileManager.default.fileExists(atPath: installedHelper.path) else { return nil }
        var code: SecStaticCode?
        var expected: SecRequirement?
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        guard let requirement,
              SecRequirementCreateWithString(requirement as CFString, [], &expected) == errSecSuccess,
              SecStaticCodeCreateWithPath(installedHelper as CFURL, [], &code) == errSecSuccess,
              let code, let expected,
              SecStaticCodeCheckValidity(code, flags, expected) == errSecSuccess,
              let version = Self.version(at: installedHelper),
              Self.compare(version, version) != nil
        else {
            throw VPhoneLaunchpadError(String(localized: "Unable to verify the installed helper. It has not been replaced."))
        }
        return version
    }

    static func version(at url: URL) -> String? {
        let info = CFBundleCopyInfoDictionaryForURL(url as CFURL) as? [String: Any]
        return info?["CFBundleVersion"] as? String
    }

    /// CFBundleVersion is numeric; reject unknown/development labels rather
    /// than guessing their ordering and possibly replacing a newer helper.
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult? {
        func components(_ value: String) -> [UInt]? {
            let parts = value.split(separator: ".", omittingEmptySubsequences: false)
            guard (1...3).contains(parts.count) else { return nil }
            let numbers = parts.compactMap { part -> UInt? in
                guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
                return UInt(part)
            }
            guard numbers.count == parts.count else { return nil }
            return numbers + Array(repeating: 0, count: 3 - numbers.count)
        }
        guard let left = components(lhs), let right = components(rhs) else { return nil }
        if left == right { return .orderedSame }
        return left.lexicographicallyPrecedes(right) ? .orderedAscending : .orderedDescending
    }
}
