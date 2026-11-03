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
    private var cancelled = false
    private var generation = 0
    private var navigationFailed = false
    private var requiresAuthorization = false
    private let sessionCheck: (@MainActor () async throws -> Bool)?
    var authenticating: Bool { automaticLogin }
    private(set) var presentationID = UUID()
    var presented = false {
        willSet { if newValue && !presented { presentationID = UUID() } }
    }
    var verified = false
    var checking = false
    var message = "正在准备下载…"
    let webView: WKWebView

    init(webView suppliedWebView: WKWebView? = nil,
         sessionCheck: (@MainActor () async throws -> Bool)? = nil) {
        let config = WKWebViewConfiguration()
        // WebKit owns the persistent website session; no password or Cookie file is exported.
        config.websiteDataStore = .default()
        webView = suppliedWebView ?? WKWebView(frame: .zero, configuration: config)
        self.sessionCheck = sessionCheck
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func reload() {
        navigationFailed = false
        if webView.url == nil { webView.load(URLRequest(url: URL(string: "https://armconverter.com/store/us")!)) }
        else { webView.reload() }
    }

    func dismiss(presentation: UUID? = nil) {
        guard presented, presentation == nil || presentation == presentationID else { return }
        if verified { presented = false }
        else { cancel() }
    }

    func invalidateSession() {
        verified = false
        requiresAuthorization = true
    }

    func cancel() {
        cancelled = true
        generation += 1
        verified = false
        automaticLogin = false
        presented = false
        webView.stopLoading()
    }

    func startAccountLogin(silently: Bool = false) {
        guard !checking, !automaticLogin else { return }
        cancelled = false
        navigationFailed = false
        requiresAuthorization = false
        verified = false
        automaticLogin = true
        submittedCredentials = false
        message = "正在准备下载…"
        presented = !silently
        webView.load(URLRequest(url: URL(string: "https://armconverter.com/auth/login?next=/store/us&direct=yes")!))
    }

    func ensureSession() async throws {
        cancelled = false
        navigationFailed = false
        defer { automaticLogin = false }
        do {
            // A navigation callback may already be probing the restored session.
            // Wait for it before deciding whether to start a fresh authorization.
            while checking {
                try Task.checkCancellation()
                if cancelled { throw CancellationError() }
                try await Task.sleep(for: .milliseconds(20))
            }
            try await ARMStoreAuthentication.ensureSession(check: {
                if self.navigationFailed { throw VPhoneLaunchpadError("下载准备失败，请检查网络后重试。") }
                guard !self.requiresAuthorization else { return false }
                guard !self.checking, !self.webView.isLoading,
                      self.webView.url?.host == "armconverter.com",
                      self.webView.url?.path.hasPrefix("/store") == true else { return false }
                do { try await self.verify(); return true }
                catch is ARMStoreLoginRequired { return false }
            }, begin: {
                if !self.automaticLogin { self.startAccountLogin(silently: true) }
            }, cancelled: { self.cancelled })
            presented = false
        } catch {
            cancel()
            message = error is CancellationError ? "下载已取消。" : "下载准备失败，请检查网络后重试。"
            throw error
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !cancelled else { return }
        let navigationGeneration = generation
        Task {
            guard !cancelled, generation == navigationGeneration else { return }
            if webView.url?.host == "armconverter.com", webView.url?.path.hasPrefix("/store") == true {
                guard !checking else { return }
                do { try await verify(); presented = false }
                catch {
                    guard !cancelled, generation == navigationGeneration else { return }
                    verified = false
                    message = "正在等待网站确认，完成后将自动继续下载。"
                }
                return
            }
            guard automaticLogin else { return }
            guard webView.url?.host == "iosgods.com" else {
                presented = true
                message = "请完成网站验证，完成后将自动继续下载。"
                return
            }
            guard let preset else {
                presented = true
                message = "请在此完成网站验证，完成后将自动继续下载。"
                return
            }
            guard webView.url?.path.hasPrefix("/oauth/authorize") == true else {
                presented = true
                return
            }
            if submittedCredentials {
                presented = true
                message = "请完成网站验证，完成后将自动继续下载。"
                return
            }
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
                guard !cancelled, generation == navigationGeneration else { return }
                if result == "submitted" { message = "正在等待网站确认…" }
                else {
                    presented = true
                    message = "请完成网站验证，完成后将自动继续下载。"
                }
            } catch {
                guard !cancelled, generation == navigationGeneration else { return }
                presented = true
                message = "请在此完成网站验证，完成后将自动继续下载。"
            }
        }
    }

    func verify() async throws {
        guard !checking else { throw VPhoneLaunchpadError("正在检查 ARM Store 登录状态，请稍后重试。") }
        guard webView.url?.host == "armconverter.com" else { throw ARMStoreLoginRequired() }
        checking = true
        let currentGeneration = generation
        defer { checking = false }
        let result: Bool
        if let sessionCheck { result = try await sessionCheck() }
        else { result = (try await webView.callAsyncJavaScript("""
            const response = await fetch('/decryptedappstore/user/info', {credentials: 'include', headers: {'X-Requested-With': 'XMLHttpRequest'}, cache: 'no-store', signal: AbortSignal.timeout(15000)});
            if (!response.ok) return false;
            const user = await response.json();
            return !!user.igid;
            """, arguments: [:], in: nil, contentWorld: .page) as? Bool) == true }
        try Task.checkCancellation()
        guard currentGeneration == generation, !cancelled else { throw CancellationError() }
        verified = result
        guard verified else { throw ARMStoreLoginRequired() }
        message = "验证完成，正在继续下载…"
    }

    func credentials(for app: VPhoneStoreApplication) async throws -> (String, String) {
        try await ensureSession()
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let url = URL(string: "https://armconverter.com/decryptedappstore/download/\(app.trackId)/\(app.bundleId)/\(app.version)")!
        let header = ARMStoreSession.cookieHeader(cookies, for: url)
        guard !header.isEmpty else { invalidateSession(); throw ARMStoreLoginRequired() }
        let agent = try await webView.evaluateJavaScript("navigator.userAgent") as? String ?? ""
        return (header, agent)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
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
        guard !cancelled else { return }
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        navigationFailed = true
        automaticLogin = false
        message = "网页加载失败，请检查网络并重新加载。"
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
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
            Text("完成验证以继续下载").font(.headline)
            Text("网站需要确认身份。完成后将自动关闭此页面并继续下载，无需再次点击下载。")
            HStack {
                Text(login.webView.url?.host ?? "armconverter.com").foregroundStyle(.secondary)
                Spacer()
                Button("重新加载") { login.reload() }.disabled(login.checking)
                Button("取消下载") { login.cancel() }
            }
            ARMStoreWebView(login: login)
            Text(login.message).foregroundStyle(.secondary)
        }.padding().frame(width: 920, height: 680)
    }
}
#endif
