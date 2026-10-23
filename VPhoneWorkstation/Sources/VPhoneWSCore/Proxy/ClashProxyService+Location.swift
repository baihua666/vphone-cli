import Foundation
import Yams

extension ClashProxyService {
    /// Read the existing endpoint only. No configuration writes or connection deletion.
    public func decodoLocation(context: VMCommandContext, expectedIP: String) async throws -> IPLocation {
        let snapshot = try snapshot(context: context)
        let route = try await validate(snapshot)
        let config = try Yams.load(yaml: snapshot.runtime) as? [String: Any] ?? [:]
        guard let node = (config["proxies"] as? [[String: Any]])?.first(where: { $0["name"] as? String == route.selected }),
              ["isp.decodo.com", "gate.decodo.com"].contains(node["server"] as? String ?? ""),
              node["type"] as? String == "http", node["tls"] as? Bool == true,
              let host = node["server"] as? String, let port = node["port"] as? Int,
              (1...65535).contains(port), let user = node["username"] as? String,
              let password = node["password"] as? String else {
            throw ProxyRouteError("当前入口不支持 Decodo/IPInfo 查询")
        }
        func escaped(_ value: String) -> String {
            value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r")
        }
        var options = "proxy = \"https://\(host):\(port)\"\nproxy-user = \"\(escaped(user + ":" + password))\"\n"
        // Reach the upstream through the existing local proxy, without changing its selection.
        if let localPort = (config["mixed-port"] ?? config["socks-port"]) as? Int, (1...65535).contains(localPort) {
            options += "preproxy = \"socks5h://127.0.0.1:\(localPort)\"\n"
        }
        let inputConfig = options
        let data = try await Task.detached {
            let process = Process(), input = Pipe(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = ["--disable", "--silent", "--fail", "--max-time", "20", "--config", "-",
                                 "https://ip.decodo.com/json?provider=IPinfo"]
            process.standardInput = input; process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            try input.fileHandleForWriting.write(contentsOf: Data(inputConfig.utf8))
            try input.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw ProxyRouteError("Decodo/IPInfo 查询失败（curl \(process.terminationStatus)）")
            }
            return data
        }.value
        let latest = try await self.route(context: context)
        guard latest.selected == route.selected, latest.endpoint == route.endpoint else {
            throw ProxyRouteError("检测期间代理入口已变化，请重新检测")
        }
        return try IPLocationLookup.decodeDecodo(data, expectedIP: expectedIP)
    }
}

extension IPLocationLookup {
    static func decodeDecodo(_ data: Data, expectedIP: String) throws -> IPLocation {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let proxy = root["proxy"] as? [String: Any] ?? [:]
        let city = root["city"] as? [String: Any] ?? [:]
        let country = root["country"] as? [String: Any] ?? [:]
        let isp = root["isp"] as? [String: Any] ?? [:]
        guard proxy["ip"] as? String == expectedIP else {
            throw ProxyRouteError("Decodo 返回的 IP 与虚拟机实测 IP 不同，请重新检测")
        }
        var object: [String: Any] = ["success": true, "ip": expectedIP]
        object["country"] = country["name"]; object["region"] = city["state"]
        object["city"] = city["name"]; object["postal"] = city["zip_code"]
        object["connection"] = ["isp": isp["isp"] ?? NSNull(), "asn": isp["asn"] ?? NSNull()]
        var result = try decode(JSONSerialization.data(withJSONObject: object), expectedIP: expectedIP)
        result.source = "Decodo / IPInfo"
        return result
    }
}
