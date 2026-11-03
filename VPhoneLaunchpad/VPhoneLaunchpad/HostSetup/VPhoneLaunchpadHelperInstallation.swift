import Foundation
import Security
import ServiceManagement

extension VPhoneLaunchpadHelperClient {
    var bundledVersion: String? { installation.bundledVersion }
    var isConfigured: Bool { installation.isConfigured }

    func installedState() -> State {
        guard isConfigured else { return .unconfigured }
        guard FileManager.default.fileExists(atPath: installation.installedHelper.path) else {
            return .notInstalled
        }
        // A file's presence alone does not establish a working, trusted peer.
        return .unknown
    }

    func refresh() async {
        let local = installedState()
        guard local == .unknown else {
            state = local
            return
        }
        do {
            guard FileManager.default.fileExists(atPath: installation.job.path) else {
                throw VPhoneLaunchpadError(String(localized: "The helper's launch service is missing. It has not been replaced."))
            }
            guard let diskVersion = try installation.installedVersion() else {
                state = .notInstalled
                return
            }
            let runningVersion = try await version()
            guard VPhoneLaunchpadHelperCompatibility.compare(runningVersion, diskVersion) == .orderedSame else {
                throw VPhoneLaunchpadError(String(localized: "The running helper does not match its installed version. Restart the helper service, then check again."))
            }
            if VPhoneLaunchpadHelperCompatibility.isCompatible(runningVersion) {
                state = .ready(runningVersion)
            } else if let bundledVersion, VPhoneLaunchpadHelperCompatibility.isCompatible(bundledVersion) {
                state = .outdated(installed: runningVersion, bundled: bundledVersion)
            } else {
                throw VPhoneLaunchpadError(String(localized: "This app does not contain a compatible helper. Update the app, then check again."))
            }
        } catch {
            // A timeout or signature failure is not an instruction to reinstall.
            state = .unavailable(error.localizedDescription)
        }
    }

    /// All callers, including automatic upgrades, pass this downgrade guard.
    func install() async throws {
        await refresh()
        if case .ready = state { return }
        guard isConfigured else {
            throw VPhoneLaunchpadError(
                String(localized: "Unable to Install Helper"),
                detail: String(localized: "This build has no signing team. Rebuild and sign the app with your team, then try again.")
            )
        }
        // Re-read after the XPC await: another app may have updated the file.
        try installation.requireUpgrade()
        switch state {
        case .notInstalled, .outdated: break
        default:
            throw VPhoneLaunchpadError(String(localized: "Unable to verify helper compatibility. It has not been replaced."))
        }
        try await Task.detached { [blessHelper] in try blessHelper() }.value
        connection?.invalidate()
        connection = nil
        await refresh()
        guard case .ready = state else {
            throw VPhoneLaunchpadError(
                String(localized: "Unable to Install Helper"),
                detail: String(localized: "The installed helper did not pass compatibility checks. Try again.")
            )
        }
    }

    func uninstall() async throws {
        let authorization = try await authorizationSession.externalForm()
        try await call { proxy, done in
            proxy.uninstallHelper(authorization: authorization) { message in
                done(message.map { VPhoneLaunchpadError($0) })
            }
        }
        connection?.invalidate()
        connection = nil
        state = .notInstalled
    }

    private typealias JobBless = @convention(c) (
        CFString,
        CFString,
        AuthorizationRef,
        UnsafeMutablePointer<Unmanaged<CFError>?>?,
    ) -> DarwinBoolean

    /// `SMJobBless`, looked up in ServiceManagement at run time. macOS 13
    /// deprecated it in favour of `SMAppService`, but it still works, and the
    /// helper's install, update and client checks are built on it
    /// (SMPrivilegedExecutables and SMAuthorizedClients). Moving to
    /// `SMAppService.daemon` would change all three. The lookup keeps that
    /// choice here instead of as a standing deprecation warning.
    private nonisolated static let jobBless: JobBless? = dlopen(
        "/System/Library/Frameworks/ServiceManagement.framework/ServiceManagement",
        RTLD_LAZY,
    )
    .flatMap { dlsym($0, "SMJobBless") }
    .map { unsafeBitCast($0, to: JobBless.self) }

    nonisolated static func bless(installation: VPhoneLaunchpadHelperCompatibility) throws {
        var authorization: AuthorizationRef?
        var status = AuthorizationCreate(nil, nil, [], &authorization)
        guard status == errAuthorizationSuccess, let authorization else {
            throw VPhoneLaunchpadError(String(localized: "Unable to Get Administrator Permission"), detail: String(localized: "Try again."))
        }
        defer { AuthorizationFree(authorization, []) }

        status = kSMRightBlessPrivilegedHelper.withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { pointer in
                var rights = AuthorizationRights(count: 1, items: pointer)
                return AuthorizationCopyRights(
                    authorization,
                    &rights,
                    nil,
                    [.interactionAllowed, .extendRights, .preAuthorize],
                    nil,
                )
            }
        }
        guard status == errAuthorizationSuccess else {
            if status == errAuthorizationCanceled {
                throw CancellationError()
            }
            throw VPhoneLaunchpadError(String(localized: "Unable to Get Administrator Permission"), detail: String(localized: "Try again."))
        }

        // Administrator approval can take time; do not overwrite a helper
        // another app upgraded while that prompt was open.
        try installation.requireUpgrade()
        var error: Unmanaged<CFError>?
        guard let jobBless = Self.jobBless,
              jobBless(kSMDomainSystemLaunchd, label as CFString, authorization, &error).boolValue
        else {
            let detail = error?.takeRetainedValue().localizedDescription ?? String(localized: "Try again.")
            throw VPhoneLaunchpadError(String(localized: "Unable to Install Helper"), detail: detail)
        }
    }

}
