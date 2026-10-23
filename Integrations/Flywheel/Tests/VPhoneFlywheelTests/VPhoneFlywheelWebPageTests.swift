import Foundation
import Testing
@testable import VPhoneFlywheel

@Suite @MainActor
struct VPhoneFlywheelWebPageTests {
    private let page = "https://business.example/path?channel=test&ip=old&ip=older#section"
    private let ip = "23.24.25.26"
    private let route = VPhoneFlywheelWebPage.Route(identity: "machine-a/session-1", endpoint: "isp.decodo.com:10001")

    @Test func replacesIPAndPreservesQueryAndFragment() throws {
        let result = try VPhoneFlywheelWebPage.url(page, ip: ip)
        #expect(result == "https://business.example/path?channel=test&ip=23.24.25.26#section")
        #expect(try VPhoneFlywheelWebPage.url("https://business.example", ip: ip) == "https://business.example?ip=23.24.25.26")
        let encoded = try VPhoneFlywheelWebPage.url("https://business.example/?name=%E4%B8%AD%E6%96%87&return=a%26b", ip: ip)
        let items = URLComponents(string: encoded)?.queryItems
        #expect(items?.first?.value == "中文")
        #expect(items?.dropFirst().first?.value == "a&b")
    }

    @Test func uncheckedIPRemovesAllIPItemsAndPreservesOtherParameters() throws {
        #expect(try VPhoneFlywheelWebPage.url(page, ip: nil) == "https://business.example/path?channel=test#section")
        #expect(try VPhoneFlywheelWebPage.url("https://business.example/?ip=old&ip#fragment", ip: nil)
                == "https://business.example/#fragment")
        #expect(try VPhoneFlywheelWebPage.url("https://business.example/?name=%E4%B8%AD%E6%96%87&return=a%26b", ip: nil)
                == "https://business.example/?name=%E4%B8%AD%E6%96%87&return=a%26b")
    }

    @Test func uncheckedIPStillVerifiesBusinessNetworkBeforeOpeningWithoutIP() async throws {
        var methods: [String] = []
        let actualIP = try await VPhoneFlywheelWebPage.open(page, includeIP: false, route: { route }, rpc: { method, params, _ in
            methods.append(method)
            if method == "network.egress" { return ["origin": "guest", "ip": ip] }
            #expect(params["url"] as? String == "https://business.example/path?channel=test#section")
            #expect(params["bundle_id"] as? String == VPhoneFlywheelWebPage.safariBundleID)
            return params
        })
        #expect(actualIP == ip)
        #expect(methods == ["network.egress", "apps.open_url"])
    }

    @Test(arguments: ["", "example.com", "file:///tmp/test", "javascript:alert(1)",
                      "https://user:password@example.com", "https://feishu.cn/", "https://a.feishu.cn/"])
    func rejectsInvalidTargets(_ input: String) {
        #expect(throws: VPhoneFlywheelError.self) { try VPhoneFlywheelWebPage.configuredURL(input) }
    }

    @Test(arguments: ["", "::1", "1.2.3", "256.2.3.4", "1.2.3.-1", "1.2.3.+4", "1.2.3.4&extra=x"])
    func rejectsInvalidIPs(_ input: String) {
        #expect(throws: VPhoneFlywheelError.self) { try VPhoneFlywheelWebPage.url(page, ip: input) }
    }

    @Test(arguments: ["other.example:443", "isp.decodo.com.evil.example:443", "isp.decodo.com:0",
                      "user@isp.decodo.com:443", "isp.decodo.com:443/path", ""])
    func rejectsNonDecodoRoutes(_ endpoint: String) {
        #expect(throws: VPhoneFlywheelError.self) {
            try VPhoneFlywheelWebPage.Route(identity: "test", endpoint: endpoint).validate()
        }
    }

    @Test func measuresGuestBeforeOpeningSpecificallyInSafari() async throws {
        var events: [String] = []
        let actualIP = try await VPhoneFlywheelWebPage.open(page, route: {
            events.append("route")
            return route
        }, rpc: { method, params, timeout in
            events.append(method)
            #expect(timeout == 30)
            if method == "network.egress" {
                #expect(params.isEmpty)
                return ["origin": "guest", "ip": ip]
            }
            #expect(params["url"] as? String == "https://business.example/path?channel=test&ip=23.24.25.26#section")
            #expect(params["bundle_id"] as? String == "com.apple.mobilesafari")
            return params
        })
        #expect(actualIP == ip)
        #expect(events == ["route", "network.egress", "route", "apps.open_url"])
    }

    @Test func invalidConfigurationAndNonDecodoRouteFailBeforeGuestRequests() async throws {
        for input in ["javascript:alert(1)", page] {
            var requested = false
            await #expect(throws: VPhoneFlywheelError.self) {
                try await VPhoneFlywheelWebPage.open(input, route: {
                    .init(identity: "other", endpoint: "other.example:443")
                }, rpc: { _, _, _ in
                    requested = true
                    return [:]
                })
            }
            #expect(!requested)
        }
        try VPhoneFlywheelWebPage.Route(identity: "native", endpoint: "gate.decodo.com:7000").validate()
    }

    @Test func refusesMissingHostOrInvalidIPWithoutOpening() async {
        for egress: [String: Any] in [[:], ["ip": ip, "origin": "host"], ["origin": "guest", "ip": "bad"]] {
            var opened = false
            await #expect(throws: VPhoneFlywheelError.self) {
                try await VPhoneFlywheelWebPage.open(page, route: { route }, rpc: { method, _, _ in
                    if method == "apps.open_url" { opened = true }
                    return egress
                })
            }
            #expect(!opened)
        }
    }

    @Test func changedRouteAbortsAndIndependentRetryUsesFreshIP() async throws {
        var routes = 0
        var opened = false
        await #expect(throws: VPhoneFlywheelError.self) {
            try await VPhoneFlywheelWebPage.open(page, route: {
                routes += 1
                return routes == 1 ? route : .init(identity: "machine-a/session-2", endpoint: route.endpoint)
            }, rpc: { method, _, _ in
                if method == "apps.open_url" { opened = true }
                return ["origin": "guest", "ip": ip]
            })
        }
        #expect(!opened)
        let retried = try await VPhoneFlywheelWebPage.open(page, route: { route }, rpc: { method, params, _ in
            if method == "network.egress" { return ["origin": "guest", "ip": "23.24.25.27"] }
            opened = true
            #expect((params["url"] as? String)?.contains("ip=23.24.25.27") == true)
            return params
        })
        #expect(opened && retried == "23.24.25.27")
    }

    @Test func failuresPropagateAndUnconfirmedSafariIsRejected() async {
        for failureMethod in ["network.egress", "apps.open_url"] {
            var methods: [String] = []
            await #expect(throws: VPhoneFlywheelError.self) {
                try await VPhoneFlywheelWebPage.open(page, route: { route }, rpc: { method, _, _ in
                    methods.append(method)
                    if method == failureMethod { throw VPhoneFlywheelError("unsupported or disconnected") }
                    return ["origin": "guest", "ip": ip]
                })
            }
            #expect(methods.last == failureMethod)
        }
        await #expect(throws: VPhoneFlywheelError.self) {
            try await VPhoneFlywheelWebPage.open(page, route: { route }, rpc: { method, _, _ in
                method == "network.egress" ? ["origin": "guest", "ip": ip] : [:]
            })
        }
    }

    @Test func cancellationAfterProbeDoesNotOpen() async {
        var opened = false
        let task = Task { @MainActor in
            try await VPhoneFlywheelWebPage.open(page, route: { route }, rpc: { method, _, _ in
                if method == "network.egress" {
                    withUnsafeCurrentTask { $0?.cancel() }
                    return ["origin": "guest", "ip": ip]
                }
                opened = true
                return [:]
            })
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!opened)
    }

    @Test func urlPreferencePersistsWithoutBusinessDatabaseChanges() throws {
        let suite = "FlywheelWebTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(page, forKey: VPhoneFlywheelWebPage.urlPreferenceKey)
        let reopened = try #require(UserDefaults(suiteName: suite))
        #expect(reopened.string(forKey: VPhoneFlywheelWebPage.urlPreferenceKey) == page)
        // Existing installations default to enabled; an explicit unchecked choice survives reopening.
        #expect(reopened.object(forKey: VPhoneFlywheelWebPage.includeIPPreferenceKey) == nil)
        defaults.set(false, forKey: VPhoneFlywheelWebPage.includeIPPreferenceKey)
        #expect(try #require(UserDefaults(suiteName: suite)).object(forKey: VPhoneFlywheelWebPage.includeIPPreferenceKey) as? Bool == false)
    }
}
