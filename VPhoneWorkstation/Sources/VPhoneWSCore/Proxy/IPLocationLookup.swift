import Foundation
import Darwin

/// Geography is a lookup of the guest-measured IP, never a host egress probe.
public struct IPLocation: Decodable, Sendable {
    public let ip: String
    public let country: String?
    public let region: String?
    public let city: String?
    public let postal: String?
    public let connection: Connection?
    let success: Bool
    public var source = "ipwho.is"
    enum CodingKeys: String, CodingKey { case ip, country, region, city, postal, connection, success }
    public struct Connection: Decodable, Sendable {
        public let isp: String?
        public let asn: Int?
    }
    public var area: String {
        let parts = [country, region, city].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "未知" : parts.joined(separator: " · ")
    }
}

public enum IPLocationLookup {
    public static func lookup(_ ip: String) async throws -> IPLocation {
        var address = in_addr()
        guard inet_pton(AF_INET, ip, &address) == 1 else {
            throw ProxyRouteError("无效的公网 IPv4")
        }
        var errors: [String] = []
        for (host, path) in [("ipwho.is", "/\(ip)"), ("ipwhois.app", "/json/\(ip)")] {
            do {
                let url = URL(string: "https://\(host)\(path)")!
                let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw ProxyRouteError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                }
                var value = try decode(data, expectedIP: ip)
                value.source = host
                return value
            } catch { errors.append("\(host)：\(error.localizedDescription)") }
        }
        throw ProxyRouteError(errors.joined(separator: "；"))
    }

    static func decode(_ data: Data, expectedIP: String) throws -> IPLocation {
        // The alternate endpoint uses top-level isp/asn rather than connection.
        var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if object["connection"] == nil, let isp = object["isp"] as? String {
            var connection: [String: Any] = ["isp": isp]
            if let asn = object["asn"] as? String,
               let number = Int(asn.replacingOccurrences(of: "AS", with: "")) { connection["asn"] = number }
            object["connection"] = connection
        }
        let value = try JSONDecoder().decode(IPLocation.self, from: JSONSerialization.data(withJSONObject: object))
        guard value.success, value.ip == expectedIP else {
            throw ProxyRouteError("位置服务未返回此 IP 的有效结果")
        }
        return value
    }
}
