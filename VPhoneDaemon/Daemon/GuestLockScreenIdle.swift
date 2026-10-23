import Foundation
import IcliKit
import notify
import VphonedNative

/// Makes Auto-Lock "Never" hold on the Lock Screen too.
///
/// Settings › Display & Brightness › Auto-Lock sets `maxInactivity`, and
/// SpringBoard applies it only while the device is unlocked. On the Lock
/// Screen it uses its own six seconds whatever the setting says, so a guest
/// that has just booted, or whose SpringBoard has just restarted, goes dark
/// before anyone looks at it.
///
/// SpringBoard reads one more value there, `SBMinimumLockscreenIdleTime` in
/// `com.apple.springboard`, and replaces the six seconds with it. vphoned
/// keeps that key at the same "never" while Auto-Lock is Never, and removes
/// it again when Auto-Lock is anything else. A value some other tool put
/// there is left alone.
///
/// SpringBoard takes the key when it starts. Setting it later does nothing
/// until SpringBoard restarts, and changing or removing it puts the six
/// seconds back at once. So this runs before anything else at startup, to be
/// ahead of SpringBoard on a boot where the key is missing.
///
/// Measured on iOS 27.0 and iPadOS 26.6.2; see
/// Research/Guest/lock_screen_idle_timer.md.
enum GuestLockScreenIdle {
    /// profiled's merged settings for user mobile. It rewrites the file and
    /// then posts `changedNotification`; ManagedConfiguration's own clients
    /// re-read it on the same signal.
    private static let settingsPath = "/var/mobile/Library/UserConfigurationProfiles/EffectiveUserSettings.plist"
    private static let changedNotification = "com.apple.managedconfiguration.effectivesettingschanged"
    private static let domain = "com.apple.springboard"
    private static let key = "SBMinimumLockscreenIdleTime"
    /// What Settings stores for "Never", in seconds.
    private static let never = Int(Int32.max)
    private static let queue = DispatchQueue(label: "vphoned.lock-screen-idle", qos: .utility)

    static func startOnStartup() {
        queue.sync { apply(reason: "startup") }
        var token: Int32 = 0
        let status = notify_register_dispatch(changedNotification, &token, queue) { _ in
            apply(reason: "settings changed")
        }
        if status != 0 {
            NSLog("vphoned: lock screen idle: cannot observe Auto-Lock changes (notify status %u)", status)
        }
    }

    /// Auto-Lock in seconds, `never` for Never, nil when profiled has not
    /// written its settings yet.
    static func autoLockSeconds() -> Int? {
        guard let data = FileManager.default.contents(atPath: settingsPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let values = plist["restrictedValue"] as? [String: Any],
              let setting = values["maxInactivity"] as? [String: Any]
        else { return nil }
        return (setting["value"] as? NSNumber)?.intValue
    }

    static func lockScreenMinimum() -> Int? {
        let value = CFPreferencesCopyValue(key as CFString, domain as CFString, "mobile" as CFString, kCFPreferencesAnyHost)
        return (value as? NSNumber)?.intValue
    }

    static func describe() -> [String: Any] {
        let autoLock = autoLockSeconds()
        let minimum = lockScreenMinimum()
        return [
            "set_supported": true,
            "auto_lock_seconds": autoLock.map { $0 as Any } ?? NSNull(),
            "never": autoLock.map { $0 >= never } ?? false,
            "lock_screen_minimum_seconds": minimum.map { $0 as Any } ?? NSNull(),
        ]
    }

    /// profiled owns this value. Wait for its effective settings rather than
    /// claiming success when the private setter merely accepted the request.
    static func setNever() throws -> [String: Any] {
        if autoLockSeconds() != never {
            var error: NSString?
            guard vp_auto_lock_never(&error) else {
                throw GuestAPIError.operationFailed(error.map(String.init) ?? "Unable to set Auto-Lock")
            }
            let deadline = ProcessInfo.processInfo.systemUptime + 10
            while autoLockSeconds() != never {
                guard ProcessInfo.processInfo.systemUptime < deadline else {
                    throw GuestAPIError.operationFailed("Auto-Lock Never was not committed by profiled; check device restrictions and retry")
                }
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        queue.sync { apply(reason: "initialization") }
        guard lockScreenMinimum() == never else {
            throw GuestAPIError.operationFailed("Lock Screen idle setting did not persist")
        }
        return describe()
    }

    private static func apply(reason: String) {
        guard let autoLock = autoLockSeconds() else {
            NSLog("vphoned: lock screen idle (%@): Auto-Lock is not readable, nothing changed", reason)
            return
        }
        let minimum = lockScreenMinimum()
        do {
            if autoLock >= never {
                guard minimum != never else { return }
                _ = try writePreference(domain: domain, key: key, value: .int(Int64(never)))
                NSLog("vphoned: lock screen idle (%@): Auto-Lock is Never, Lock Screen follows from the next SpringBoard start", reason)
            } else if minimum == never {
                _ = try deletePreference(domain: domain, key: key)
                NSLog("vphoned: lock screen idle (%@): Auto-Lock is %d s, Lock Screen is back to its own timeout", reason, autoLock)
            }
        } catch {
            NSLog("vphoned: lock screen idle (%@): %@", reason, String(describing: error))
        }
    }
}
