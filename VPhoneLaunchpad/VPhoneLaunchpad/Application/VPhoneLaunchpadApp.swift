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
        #if VPHONE_CUSTOM_DECODO_PRIVATE_DEFAULTS
        do { try VPhoneLaunchpadDecodoPrivateDefaults.install() }
        catch { NSLog("Decodo defaults: %@", error.localizedDescription) }
        #endif
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
            #if VPHONE_CUSTOM_DISTRIBUTION
            VPhoneLaunchpadAppUpdateCommands(model: model)
            #endif
            CommandGroup(replacing: .newItem) {
                Button("New…") { model.machineSheetRequest = .newMachine }
                    .keyboardShortcut("n")
                    .disabled(model.bundles.defaultVersion == nil)
                Button("Import…") { model.machines.chooseImport() }
                    .keyboardShortcut("o")
                Divider()
                Button("Downloaded Firmware…") { model.present(.ipswCache) }
                if model.machines.hasTemplates {
                    Button("Templates…") { model.present(.templates) }
                }
            }
            // Now rather than on the next five-second tick: the machine list,
            // then the templates, which also measures disk use again.
            CommandGroup(before: .toolbar) {
                Button("Refresh") {
                    Task {
                        await model.machines.refresh()
                        await model.machines.refreshTemplates()
                    }
                }
                .keyboardShortcut("r")
                // Every command Launchpad ran, not one machine's: here rather
                // than in a machine's menu.
                Button("Recent Commands") { model.machineSheetRequest = .commands }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Divider()
            }
            // The selected machines' actions, as the toolbar's Actions menu
            // has them, with shortcuts.
            CommandGroup(after: .pasteboard) {
                Divider()
                VPhoneLaunchpadMachineActions(machines: model.machines.selectedMachines, placement: .editMenu)
                    .environment(model)
            }
            CommandMenu("Machine") {
                VPhoneLaunchpadMachineActions(machines: model.machines.selectedMachines, placement: .machineMenu)
                    .environment(model)
            }
            CommandGroup(after: .appSettings) {
                Button("Host Setup…") { model.present(.hostSetup) }
                Button("Core Bundle…") { model.present(.coreBundle) }
            }
        }

        WindowGroup("代理出口", id: "proxy-egress", for: URL.self) { $path in
            VPhoneLaunchpadProxyWindow(path: path).environment(model)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultWindowPlacement { _, context in
            let available = context.defaultDisplay.visibleRect
            return WindowPlacement(.center, size: CGSize(
                width: min(600, available.width - 32), height: min(560, available.height - 56)))
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

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

        #if VPHONE_CUSTOM_DISTRIBUTION
        Window("开始使用", id: "distribution") {
            VPhoneDistributionView().environment(model)
        }
        .defaultSize(width: 800, height: 760)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        #endif

        #if VPHONE_CUSTOM_DISTRIBUTION
        Window("App 更新", id: "app-update") {
            VPhoneLaunchpadAppUpdateView().environment(model)
        }
        .defaultSize(width: 480, height: 310)
        .windowResizability(.contentSize)
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
/// file, not a pipe). A machine being created, an import and an export do
/// not survive, so quitting then asks first.
@MainActor
final class VPhoneLaunchpadAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: VPhoneLaunchpadModel? {
        didSet { importOpened() }
    }

    /// Archives opened from Finder before the window gave us the model.
    private var opened: [URL] = []
    private let dockPolicy = VPhoneLaunchpadDockPolicy()
    /// Set once the user confirms closing the last window while a machine is
    /// being created, so the terminate path that follows does not ask again.
    private var confirmedClose = false

    func applicationDidFinishLaunching(_: Notification) {
        dockPolicy.start()
    }

    /// A `.vpea` opened in Finder, or dropped on the Dock icon, is imported
    /// into the default library, as Import… would; an IPSW is added to the
    /// IPSW cache.
    func application(_: NSApplication, open urls: [URL]) {
        opened += urls.filter(\.isFileURL)
        importOpened()
    }

    private func importOpened() {
        guard let model, !opened.isEmpty else {
            return
        }
        let archives = opened.filter { !VPhoneLaunchpadIPSWImport.isIPSW($0) }
        model.ipswImport.register(opened, model: model)
        opened = []
        Task {
            for archive in archives {
                await model.machines.importArchive(archive)
            }
        }
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
        #if VPHONE_CUSTOM_DISTRIBUTION
        if model?.distribution.busy == true || model?.appUpdates.busy == true {
            let alert = NSAlert()
            alert.messageText = "下载、安装或镜像导入正在进行"
            alert.informativeText = "请先暂停下载，或等待 App 准备／Core 安装／镜像导入完成后再退出。"
            alert.runModal()
            return .terminateCancel
        }
        #endif
        guard let model else {
            return .terminateNow
        }
        if !confirmedClose, model.machines.hasActiveCreation || model.machines.hasActiveTransfer, !confirmStopWork() {
            return .terminateCancel
        }
        guard model.machines.hasActiveTransfer else {
            return .terminateNow
        }
        // A `vm import` or `vm export` left behind would go on writing with
        // nobody reading its output. Stopped, each removes what it wrote.
        Task {
            await model.machines.stopTransfers()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// The close button, Close menu item and ⌘W all ask here, while the
    /// window is still up. Without the menu bar, closing the last window
    /// quits, so the alert says Quit. Cancel refuses the close. In menu bar
    /// mode closing only hides the window, so no confirmation is needed.
    func windowShouldClose(_: NSWindow) -> Bool {
        guard !VPhoneLaunchpadMenuBar.isEnabled, let model,
              model.machines.hasActiveCreation || model.machines.hasActiveTransfer
        else {
            return true
        }
        guard confirmStopWork() else {
            return false
        }
        confirmedClose = true
        return true
    }

    private func confirmStopWork() -> Bool {
        let alert = NSAlert()
        if model?.machines.hasActiveCreation == true {
            alert.messageText = String(localized: "Stop Creating Machine?")
            alert.informativeText = String(
                localized: "Quitting stops creating this machine. You can retry later from the step where it stopped.",
            )
        } else {
            alert.messageText = String(localized: "Stop Importing and Exporting?")
            alert.informativeText = String(
                localized: "Quitting stops every import and export under way and removes what they had written.",
            )
        }
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
    private nonisolated(unsafe) weak var forwarded: NSWindowDelegate?

    init(delegate: VPhoneLaunchpadAppDelegate) {
        self.delegate = delegate
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
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

    override nonisolated func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || forwarded?.responds(to: selector) == true
    }

    override nonisolated func forwardingTarget(for selector: Selector!) -> Any? {
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

    func makeNSView(context _: Context) -> NSView {
        MainActor.assumeIsolated {
            VPhoneLaunchpadWindowCloseHook(delegate: delegate)
        }
    }

    func updateNSView(_: NSView, context _: Context) {}
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
