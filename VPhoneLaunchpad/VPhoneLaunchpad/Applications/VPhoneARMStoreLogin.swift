#if VPHONE_CUSTOM_APPLICATION_MANAGEMENT
import SwiftUI
import WebKit
import VPhoneApplicationManagement

@MainActor @Observable
final class VPhoneARMStoreLogin: NSObject, WKNavigationDelegate, WKUIDelegate {
    private var preset: (account: String, password: String)? {
        #if VPHONE_CUSTOM_ARM_STORE_PRESET_ACCOUNT
        (VPhonePrivateARMStoreAccount.account, VPhonePrivateARMStoreAccount.password)
        #else
        nil
        #endif
    }
    private var automaticLogin = false
    private var submittedCredentials = false
    var authenticating: Bool { automaticLogin }
    var presented = false
    var verified = false
    var checking = false
    var message = "请在 APP 内登录 ARM Store。"
    let webView: WKWebView

    override init() {
        let config = WKWebViewConfiguration()
        // WebKit owns the persistent website session; no password or Cookie file is exported.
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func open() {
        presented = true
        if webView.url == nil { reload() }
    }
    func reload() { webView.load(URLRequest(url: URL(string: "https://armconverter.com/store/us")!)) }

    func startAccountLogin(silently: Bool = false) {
        guard !checking, !automaticLogin else { return }
        guard preset != nil else {
            message = "此构建未配置预设账号，请在网页登录后点击确认登录。"
            presented = true
            webView.load(URLRequest(url: URL(string: "https://armconverter.com/auth/login?next=/store/us&direct=yes")!))
            return
        }
        verified = false
        automaticLogin = true
        submittedCredentials = false
        message = "正在使用预设账号登录…"
        presented = !silently
        webView.load(URLRequest(url: URL(string: "https://armconverter.com/auth/login?next=/store/us&direct=yes")!))
    }

    func ensureSession() async throws {
        if !automaticLogin, webView.url?.host == "armconverter.com" {
            do { try await verify(); return } catch { verified = false }
        }
        if !automaticLogin { startAccountLogin(silently: true) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(60))
        do {
            while automaticLogin {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else {
                    throw VPhoneLaunchpadError("ARM Store 登录超时，请检查网络或在登录窗口处理验证后重试。")
                }
                try await Task.sleep(for: .milliseconds(200))
            }
        } catch {
            automaticLogin = false
            webView.stopLoading()
            message = error is CancellationError ? "登录已取消。" : error.localizedDescription
            throw error
        }
        guard verified else {
            presented = true
            throw VPhoneLaunchpadError(message)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard automaticLogin else { return }
        Task {
            if webView.url?.host == "armconverter.com", webView.url?.path.hasPrefix("/store") == true {
                defer { automaticLogin = false }
                do { try await verify(); presented = false }
                catch { verified = false; message = "账号返回商店，但登录未确认。请查看网页提示后重试。" }
                return
            }
            guard webView.url?.host == "iosgods.com",
                  webView.url?.path.hasPrefix("/oauth/authorize") == true else { return }
            if submittedCredentials {
                automaticLogin = false
                message = "登录尚未成功。请查看官网错误提示；不会自动重复提交账号密码。"
                return
            }
            guard let preset else { automaticLogin = false; return }
            submittedCredentials = true
            do {
                let result = try await webView.callAsyncJavaScript("""
                    const password = document.querySelector('input[type="password"]');
                    const form = password?.closest('form');
                    const account = form?.querySelector('input[type="email"], input[type="text"]');
                    if (!form || !account || !password) return 'missing';
                    account.value = accountValue;
                    password.value = passwordValue;
                    for (const input of [account, password]) {
                        input.dispatchEvent(new Event('input', {bubbles: true}));
                        input.dispatchEvent(new Event('change', {bubbles: true}));
                    }
                    if (form.querySelector('iframe[src*="recaptcha"], iframe[src*="hcaptcha"], .g-recaptcha, .h-captcha')) return 'challenge';
                    const submit = form.querySelector('button[type="submit"], input[type="submit"]');
                    if (!submit) return 'missing';
                    form.requestSubmit(submit);
                    return 'submitted';
                    """, arguments: ["accountValue": preset.account, "passwordValue": preset.password],
                    in: nil, contentWorld: .page) as? String
                if result == "submitted" { message = "账号已提交，等待官网验证…" }
                else {
                    automaticLogin = false
                    message = result == "challenge" ? "账号已填写，请在官网完成验证码后提交。" : "未找到官网登录表单，请检查当前页面。"
                }
            } catch {
                automaticLogin = false
                message = "自动填写未完成，请检查网页后重试。"
            }
        }
    }

    func verify() async throws {
        guard !checking else { throw VPhoneLaunchpadError("正在检查 ARM Store 登录状态，请稍后重试。") }
        guard webView.url?.host == "armconverter.com" else { throw ARMStoreLoginRequired() }
        checking = true
        defer { checking = false }
        let result = try await webView.callAsyncJavaScript("""
            const response = await fetch('/decryptedappstore/user/info', {credentials: 'include', headers: {'X-Requested-With': 'XMLHttpRequest'}, cache: 'no-store', signal: AbortSignal.timeout(15000)});
            if (!response.ok) return false;
            const user = await response.json();
            return !!user.igid;
            """, arguments: [:], in: nil, contentWorld: .page)
        verified = (result as? Bool) == true
        guard verified else { throw ARMStoreLoginRequired() }
        message = "已登录；会话保存在这台 Mac，下载可能消耗账户额度。"
    }

    func confirm() {
        Task {
            do { try await verify(); presented = false }
            catch { verified = false; message = "尚未确认登录成功。请完成网页登录后重试；网络或验证失败可点重新加载。" }
        }
    }

    func credentials(for app: VPhoneStoreApplication) async throws -> (String, String) {
        try await ensureSession()
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let url = URL(string: "https://armconverter.com/decryptedappstore/download/\(app.trackId)/\(app.bundleId)/\(app.version)")!
        let header = ARMStoreSession.cookieHeader(cookies, for: url)
        guard !header.isEmpty else { verified = false; open(); throw ARMStoreLoginRequired() }
        let agent = try await webView.evaluateJavaScript("navigator.userAgent") as? String ?? ""
        return (header, agent)
    }

    func logout() {
        Task {
            checking = true
            let store = webView.configuration.websiteDataStore
            let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
            let owned = records.filter { $0.displayName == "armconverter.com" || $0.displayName == "iosgods.com" }
            await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: owned)
            verified = false
            message = "已清除本机 ARM Store 登录，请重新登录。"
            checking = false
            reload()
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, ARMStoreSession.allowsNavigation(url) else {
            if navigationAction.targetFrame?.isMainFrame != false {
                message = "此登录方式尚未接通。Google 登录需使用原浏览器；不要更换账号或改用其它账号密码。"
            }
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ARMStoreSession.allowsNavigation(url) {
            webView.load(navigationAction.request)
        }
        return nil
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        automaticLogin = false
        message = "网页加载失败，请检查网络并重新加载。"
    }
}

private struct ARMStoreWebView: NSViewRepresentable {
    let login: VPhoneARMStoreLogin
    func makeNSView(context: Context) -> WKWebView { login.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

struct VPhoneARMStoreLoginView: View {
    let login: VPhoneARMStoreLogin
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("登录 ARM Store").font(.headline)
            Text("使用预设账号完成官网密码登录；成功后自动确认 ARM Store 会话。验证码须在网页完成。")
            HStack {
                Text(login.webView.url?.host ?? "armconverter.com").foregroundStyle(.secondary)
                Spacer()
                Button("预设账号登录") { login.startAccountLogin() }.disabled(login.checking || login.authenticating)
                Button("返回商店／重新加载") { login.reload() }.disabled(login.authenticating)
                Button("关闭") { login.presented = false }
            }
            ARMStoreWebView(login: login)
            Text(login.message).foregroundStyle(.secondary)
            Button(login.checking ? "正在确认…" : "确认登录") { login.confirm() }.disabled(login.checking)
        }.padding().frame(width: 920, height: 680)
    }
}
#endif
