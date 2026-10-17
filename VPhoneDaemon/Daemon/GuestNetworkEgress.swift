import Darwin
import Foundation

/// A bounded, guest-originated HTTPS check. No host fallback or arbitrary URL.
enum GuestNetworkEgress {
    static let endpoint = URL(string: "https://api.ipify.org?format=json")!

    private final class Response: @unchecked Sendable {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, URLResponse), Error>?
    }

    static func probe() throws -> [String: Any] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = Response()
        let task = session.dataTask(with: request) { data, urlResponse, error in
            if let error { response.result = .failure(error) }
            else if let data, let urlResponse { response.result = .success((data, urlResponse)) }
            else { response.result = .failure(GuestAPIError.operationFailed("Empty egress response")) }
            response.semaphore.signal()
        }
        task.resume()
        guard response.semaphore.wait(timeout: .now() + 17) == .success else {
            task.cancel()
            throw GuestAPIError.operationFailed("Guest egress check timed out")
        }
        let (data, raw) = try response.result!.get()
        guard let http = raw as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme == "https", http.url?.host == endpoint.host else {
            throw GuestAPIError.operationFailed("Egress service returned an unexpected HTTP response")
        }
        return ["ip": try parse(data), "source": endpoint.absoluteString,
                "origin": "guest", "checked_at": ISO8601DateFormatter().string(from: Date())]
    }

    static func parse(_ data: Data) throws -> String {
        guard data.count <= 4096,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ip = object["ip"] as? String else {
            throw GuestAPIError.operationFailed("Invalid egress response")
        }
        var address = in_addr()
        guard ip.withCString({ inet_pton(AF_INET, $0, &address) }) == 1 else {
            throw GuestAPIError.operationFailed("Egress service did not return IPv4")
        }
        let octets = ip.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets[0] != 0, octets[0] != 10,
              octets[0] != 127, octets[0] < 224,
              !(octets[0] == 169 && octets[1] == 254),
              !(octets[0] == 172 && (16...31).contains(octets[1])),
              !(octets[0] == 192 && octets[1] == 168),
              !(octets[0] == 100 && (64...127).contains(octets[1])) else {
            throw GuestAPIError.operationFailed("Egress service returned a non-public IPv4 address")
        }
        return ip
    }
}
