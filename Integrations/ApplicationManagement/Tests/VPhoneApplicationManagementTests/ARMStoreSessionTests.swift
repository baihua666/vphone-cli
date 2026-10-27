import Foundation
import XCTest
@testable import VPhoneApplicationManagement

final class ARMStoreSessionTests: XCTestCase {
    func testCookiesAreScopedToSupplierPathAndExpiry() {
        func cookie(_ name: String, domain: String = "armconverter.com", path: String = "/", expires: Date? = nil) -> HTTPCookie {
            var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: "secret", .domain: domain, .path: path, .secure: "TRUE"]
            if let expires { properties[.expires] = expires }
            return HTTPCookie(properties: properties)!
        }
        let cookies = [cookie("session"), cookie("foreign", domain: "iosgods.com"),
                       cookie("expired", expires: Date(timeIntervalSince1970: 1)),
                       cookie("wrongPath", path: "/decryptedappstore/downloads"),
                       cookie("specific", domain: ".armconverter.com", path: "/decryptedappstore")]
        let url = URL(string: "https://armconverter.com/decryptedappstore/download/1/test.app/1")!
        XCTAssertEqual(ARMStoreSession.cookieHeader(cookies, for: url), "specific=secret; session=secret")
        XCTAssertEqual(ARMStoreSession.cookieHeader(cookies, for: URL(string: "https://cdn.example.com/")!), "")
        XCTAssertEqual(ARMStoreSession.cookieHeader(cookies, for: URL(string: "http://armconverter.com/")!), "")
    }
    func testNavigationRejectsUnrelatedSitesAndExternalApps() {
        for url in ["https://armconverter.com/", "https://iosgods.com/login", "https://accounts.iosgods.com/"] {
            XCTAssertTrue(ARMStoreSession.allowsNavigation(URL(string: url)!))
        }
        for url in ["https://feishu.cn/", "feishu://open", "http://armconverter.com/", "https://armconverter.com.evil.com/", "https://eviliosgods.com/", "file:///tmp/test"] {
            XCTAssertFalse(ARMStoreSession.allowsNavigation(URL(string: url)!))
        }
    }
    func testInMemorySessionRequiresNoCookieFileAndRejectsHeaderInjection() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa").path
        let options = try Options(["--app-id", "1", "--bundle-id", "test.app", "--version", "1", "--download", "--output", output], hasSession: true)
        let client = try Client(options, sessionCookie: "session=value")
        XCTAssertEqual(client.request(URL(string: client.base)!).value(forHTTPHeaderField: "Cookie"), "session=value")
        XCTAssertThrowsError(try Client(options, sessionCookie: ""))
        XCTAssertThrowsError(try Client(options, sessionCookie: "session=value\r\nInjected: true"))
    }
}
