import AppKit
import SwiftUI
import VPhoneWSCore

@main
struct VPhoneLaunchpadApp: App {
    @NSApplicationDelegateAdaptor(VPhoneLaunchpadAppDelegate.self) private var delegate
    @State private var model = VPhoneLaunchpadModel()
    @AppStorage(VPhoneLaunchpadMenuBar.key) private var showsInMenuBar = false

    init() {
        // AppKit must not restore saved window state. Everything starts from
        // the window's task, so a launch that restores a state with no window
        // in it never opens the control socket, and after a crash AppKit
        // holds the launch at an alert about reopening windows.
        UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
    }

    var body: some Scene {
        Window(Text(verbatim: "vphone-launchpad"), id: "main") {
            VPhoneLaunchpadRootView()
                .environment(model)
                .confirmCloseDuringCreation(delegate)
                .onAppear { delegate.model = model }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        // Nor is any saved: the window's frame is kept under its own name.
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Downloaded IPSWs…") { model.present(.ipswCache) }
            }
            CommandGroup(after: .appSettings) {
                Button("Host Setup…") { model.present(.hostSetup) }
                Button("Core Bundle…") { model.present(.coreBundle) }
            }
        }

        Window("FLYWHEEL", id: "flywheel") {
            VPhoneLaunchpadFlywheelWindow()
                .environment(model)
        }
        .defaultSize(width: 1100, height: 650)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        #if VPHONE_CUSTOM_APPLICATION_MANAGEMENT
        Window("应用管理", id: "applications") {
            VPhoneLaunchpadApplicationsView().environment(model)
        }
        .defaultSize(width: 900, height: 650)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        #endif

        Settings { DecodoAccountSettingsView() }

        MenuBarExtra(isInserted: $showsInMenuBar) {
            VPhoneLaunchpadMenuBarMenu()
                .environment(model)
        } label: {
            Label {
                Text(verbatim: "vphone-launchpad")
            } icon: {
                Image(systemName: "iphone")
            }
        }
    }
}

/// Guests keep running when Launchpad quits (their output goes to a log
/// file, not a pipe). A machine being created does not survive, so quitting
/// then asks first.
@MainActor
final class VPhoneLaunchpadAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: VPhoneLaunchpadModel?
    private let dockPolicy = VPhoneLaunchpadDockPolicy()
    /// Set once the user confirms closing the last window while a machine is
    /// being created, so the terminate path that follows does not ask again.
    private var confirmedClose = false

    func applicationDidFinishLaunching(_: Notification) {
        dockPolicy.start()
    }

    /// In menu bar mode the app stays behind in the menu bar. Closing the
    /// window while a machine is being created is refused in
    /// `windowShouldClose`, so this is not asked until the window is gone.
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        !VPhoneLaunchpadMenuBar.isEnabled
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        #if DEBUG
            if VPhoneLaunchpadPreview.isActive {
                return .terminateNow
            }
        #endif
        if confirmedClose {
            return .terminateNow
        }
        guard let model, model.machines.hasActiveCreation else {
            return .terminateNow
        }
        return confirmStopCreation() ? .terminateNow : .terminateCancel
    }

    /// The close button, Close menu item and ⌘W all ask here, while the
    /// window is still up. Without the menu bar, closing the last window
    /// quits, so the alert says Quit. Cancel refuses the close. In menu bar
    /// mode closing only hides the window, so no confirmation is needed.
    func windowShouldClose(_ window: NSWindow) -> Bool {
        guard !VPhoneLaunchpadMenuBar.isEnabled, let model, model.machines.hasActiveCreation else {
            return true
        }
        guard confirmStopCreation() else {
            return false
        }
        confirmedClose = true
        return true
    }

    private func confirmStopCreation() -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Stop Creating Machine?")
        alert.informativeText = String(
            localized: "Quitting stops creating this machine. You can retry later from the step where it stopped.",
        )
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// Installed in the main window's content so that window, and no other, asks
/// before closing while a machine is being created. SwiftUI already owns the
/// window delegate, so the question is forwarded and every other message goes
/// to the delegate that was there.
private final class VPhoneLaunchpadWindowCloseHook: NSView, NSWindowDelegate {
    private weak var delegate: VPhoneLaunchpadAppDelegate?
    /// Read from `NSObject`'s nonisolated forwarding methods. AppKit calls
    /// those, and moves this view between windows, on the main thread.
    nonisolated(unsafe) private weak var forwarded: NSWindowDelegate?

    init(delegate: VPhoneLaunchpadAppDelegate) {
        self.delegate = delegate
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, window.delegate !== self else { return }
        forwarded = window.delegate
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if forwarded?.windowShouldClose?(sender) == false {
            return false
        }
        return delegate?.windowShouldClose(sender) ?? true
    }

    nonisolated override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || forwarded?.responds(to: selector) == true
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        if forwarded?.responds(to: selector) == true {
            return forwarded
        }
        return super.forwardingTarget(for: selector)
    }
}

extension View {
    /// Asks before this window closes while a machine is being created.
    func confirmCloseDuringCreation(_ delegate: VPhoneLaunchpadAppDelegate) -> some View {
        background {
            VPhoneLaunchpadWindowCloseInstaller(delegate: delegate)
        }
    }
}

private struct VPhoneLaunchpadWindowCloseInstaller: NSViewRepresentable {
    let delegate: VPhoneLaunchpadAppDelegate

    func makeNSView(context: Context) -> NSView {
        MainActor.assumeIsolated {
            VPhoneLaunchpadWindowCloseHook(delegate: delegate)
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct DecodoAccountSettingsView: View {
    @State private var account = DecodoAccount()
    @State private var source = ""
    @State private var message = ""
    @State private var busy = false
    var body: some View {
        Form {
            Section("Decodo 账号") {
                TextField("网站登录邮箱", text: $account.email)
                SecureField("网站登录密码", text: $account.password)
                SecureField("Public API Key（可选）", text: $account.apiKey)
                Text(DecodoAuthorizationPolicy.explanation).font(.caption).foregroundStyle(.secondary)
            }
            Section("授权会话（可选）") {
                SecureField("JWT-AUTH", text: $account.accessToken)
                SecureField("refresh_token", text: $account.refreshToken)
                Text("请求时优先使用现有会话；401 后刷新一次，再尝试账号登录。验证码或二次验证需在官网完成。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("配置文件") {
                Text("当前来源：" + source).font(.caption).textSelection(.enabled)
                Text("用户设置优先；没有用户文件时读取：" + DecodoAccount.fallbackPath).font(.caption).textSelection(.enabled)
                Text("明文文件，仅本机用户可读写。请单独复制到其它设备，不提交 Git。网站账号与代理账号分别管理。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("保存用户设置") { save() }
                Button("保存并验证 / 续期") {
                    guard save() else { return }
                    busy = true
                    Task { @MainActor in
                        defer { busy = false }
                        do {
                            let data = try await DecodoAccountSession.shared.subscriptions()
                            let locations = try DecodoLocations.decode(data)
                            account = try DecodoAccount.load().account
                            message = "授权成功，读取 \(locations.count - 1) 个 ISP 地区。未修改虚拟机出口。"
                        } catch { message = error.localizedDescription }
                    }
                }
                Button("重新读取") { load() }
            }
            if busy { ProgressView() }
            Text(message).font(.callout).textSelection(.enabled)
        }.formStyle(.grouped).padding().frame(width: 620, height: 590).disabled(busy).onAppear { load() }
    }
    private func load() {
        do { let loaded = try DecodoAccount.load(); account = loaded.account; source = loaded.path; message = "已读取配置。" }
        catch { message = error.localizedDescription }
    }
    @discardableResult private func save() -> Bool {
        do {
            // An account change must not reuse the old account's authorized session.
            if let old = try? DecodoAccount.load().account,
               (old.email != account.email || old.password != account.password),
               old.accessToken == account.accessToken, old.refreshToken == account.refreshToken {
                account.accessToken = ""; account.refreshToken = ""
            }
            try account.save(); source = DecodoAccount.userPath
            message = "用户设置已保存；尚未验证授权。"
            return true
        } catch { message = error.localizedDescription; return false }
    }
}
