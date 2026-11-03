import AppKit
import WebKit
import VPhoneApplicationManagement

struct VPhoneLaunchpadError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// Substitute only WebKit transport; compile and exercise the production adapter.
@MainActor final class TestStoreWebView: WKWebView {
    var pageURL = URL(string: "https://armconverter.com/store/us")!
    var loads = 0
    override var url: URL? { pageURL }
    override var isLoading: Bool { false }
    override func load(_ request: URLRequest) -> WKNavigation? {
        loads += 1
        pageURL = request.url!
        return nil
    }
}

@MainActor final class WebsiteState {
    var authenticated = false
    var completion: CheckedContinuation<Bool, Never>?
}

@main struct ARMStoreLoginTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let web = TestStoreWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let website = WebsiteState()
        let login = VPhoneARMStoreLogin(webView: web, sessionCheck: { website.authenticated })
        let pending = Task { try await login.ensureSession() }
        while web.loads == 0 { await Task.yield() }
        precondition(login.authenticating, "Without a preset account the download must remain pending")
        web.pageURL = URL(string: "https://iosgods.com/oauth/authorize")!
        login.webView(web, didFinish: nil)
        while !login.presented { await Task.yield() }
        precondition(!login.message.contains("预设账号"))
        website.authenticated = true
        web.pageURL = URL(string: "https://armconverter.com/store/us")!
        login.webView(web, didFinish: nil)
        try await pending.value
        precondition(login.verified && !login.presented, "Website success must resume and dismiss automatically")
        login.dismiss()
        precondition(login.verified, "Automatic sheet dismissal must preserve a confirmed session")
        let previousLoads = web.loads
        try await login.ensureSession()
        precondition(web.loads == previousLoads, "An existing session must not reopen authorization")

        website.authenticated = false
        let cancelled = Task { try await login.ensureSession() }
        while web.loads == previousLoads { await Task.yield() }
        login.cancel()
        do { try await cancelled.value; fatalError("Cancelled download continued") }
        catch is CancellationError {}
        precondition(!login.verified && !login.presented)

        let delayedWeb = TestStoreWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let late = VPhoneARMStoreLogin(webView: delayedWeb, sessionCheck: {
            await withCheckedContinuation { website.completion = $0 }
        })
        let verification = Task { try await late.verify() }
        while website.completion == nil { await Task.yield() }
        late.cancel()
        website.completion!.resume(returning: true)
        do { try await verification.value; fatalError("Late verification revived cancelled download") }
        catch is CancellationError {}
        precondition(!late.verified && !late.presented)

        let retryWeb = TestStoreWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let recovery = VPhoneARMStoreLogin(webView: retryWeb, sessionCheck: { website.authenticated })
        let failed = Task { try await recovery.ensureSession() }
        while retryWeb.loads == 0 { await Task.yield() }
        recovery.webView(retryWeb, didFailProvisionalNavigation: nil,
                         withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        do { try await failed.value; fatalError("Expected a network failure") }
        catch is VPhoneLaunchpadError {}
        website.authenticated = true
        retryWeb.pageURL = URL(string: "https://armconverter.com/store/us")!
        try await recovery.ensureSession()
        precondition(recovery.verified, "A failed download must not poison the next attempt")

        let beforeReauthorization = retryWeb.loads
        recovery.invalidateSession()
        let reauthorized = Task { try await recovery.ensureSession() }
        while retryWeb.loads == beforeReauthorization { await Task.yield() }
        precondition(!recovery.verified, "Download API rejection must force authorization even if user/info was valid")
        retryWeb.pageURL = URL(string: "https://armconverter.com/store/us")!
        try await reauthorized.value
        precondition(recovery.verified)

        recovery.presented = true
        let oldPresentation = recovery.presentationID
        recovery.presented = false
        recovery.invalidateSession()
        recovery.presented = true
        recovery.dismiss(presentation: oldPresentation)
        precondition(recovery.presented, "An old automatic dismissal cannot cancel a new verification")
        recovery.dismiss(presentation: recovery.presentationID)
        precondition(!recovery.presented)
        print("ARM Store WebKit adapter: automatic confirmation, no-preset continuation, session reuse and cancellation passed")
    }
}
