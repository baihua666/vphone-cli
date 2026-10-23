import Foundation
import Testing
@testable import VPhoneWSCore

private actor AccountTransport {
    var requests: [URLRequest] = []
    let statuses: [Int]
    init(_ statuses: [Int]) { self.statuses = statuses }
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let index = requests.count; requests.append(request)
        let status = statuses[index]
        let renewing = request.url!.path.contains("refresh") || request.url!.path.contains("login")
        let data = renewing ? Data(#"{"token":"new-access","refresh_token":"new-refresh"}"#.utf8) : Data("{}".utf8)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
@Test func decodoSessionRefreshes401AndRetriesWithoutPasswordOrAPIKey() async throws {
    let transport = AccountTransport([401,200,200])
    let session = DecodoAccountSession(transport: { try await transport.send($0) })
    var account = DecodoAccount(); account.accessToken = "old"; account.refreshToken = "refresh"; account.apiKey = "not-for-isp"
    _ = try await session.authorizedSubscriptions(account: &account)
    #expect(account.accessToken == "new-access")
    #expect(account.refreshToken == "new-refresh")
    let requests = await transport.requests
    #expect(requests.map { $0.url!.path } == ["/subscription-api/v1/subscriptions", "/api/v1/token/refresh", "/subscription-api/v1/subscriptions"])
    #expect(requests[2].value(forHTTPHeaderField: "Cookie")?.contains("JWT-AUTH=new-access") == true)
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
}
@Test func decodoForbiddenDoesNotRefreshOrRepeatedlyLogin() async throws {
    let transport = AccountTransport([403])
    let session = DecodoAccountSession(transport: { try await transport.send($0) })
    var account = DecodoAccount(); account.accessToken = "old"; account.refreshToken = "refresh"
    await #expect(throws: (any Error).self) { try await session.authorizedSubscriptions(account: &account) }
    #expect(await transport.requests.count == 1)
}
@Test func decodoMissingCredentialsDoesNotSendAnonymousLogin() async throws {
    let transport = AccountTransport([])
    let session = DecodoAccountSession(transport: { try await transport.send($0) })
    var account = DecodoAccount()
    await #expect(throws: (any Error).self) { try await session.authorizedSubscriptions(account: &account) }
    #expect(await transport.requests.isEmpty)
}
@Test func decodoAccountFileRoundTripIsPrivate() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    defer { try? FileManager.default.removeItem(atPath: path) }
    var account = DecodoAccount(); account.email = "test@example.invalid"; account.password = "fixture"
    try account.save(path: path)
    let loaded = try JSONDecoder().decode(DecodoAccount.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    #expect(loaded == account)
    #expect((try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int) == 0o600)
    #expect(!DecodoAuthorizationPolicy.ispUsesPublicAPIKey)
}

@Test func decodoExpiredRefreshFallsBackToSingleAccountLogin() async throws {
    let transport = AccountTransport([401,401,200,200])
    let session = DecodoAccountSession(transport: { try await transport.send($0) })
    var account = DecodoAccount(); account.accessToken = "old"; account.refreshToken = "expired"
    account.email = "test@example.invalid"; account.password = "fixture"
    _ = try await session.authorizedSubscriptions(account: &account)
    let requests = await transport.requests
    #expect(requests.count == 4)
    #expect(requests[2].url!.path == "/api/v1/users/login")
    let body = try JSONSerialization.jsonObject(with: requests[2].httpBody!) as! [String: String]
    #expect(body["username"] == account.email)
    #expect(body["password"] == "fixture")
    #expect(account.accessToken == "new-access")
}
