import CryptoKit
import Foundation
import SystemConfiguration

/// Wire format shared with VPhoneCoreKit.VPhoneNativeProxy; covered by contract tests.
struct NativeDecodoConfiguration: Codable, Sendable {
    var host: String
    var address: String
    var port: Int
    var username: String
    var password: String
    var interface: String
    var dnsAddress = "1.1.1.1"
}

/// Standalone transport: no Clash configuration, API, or process-path dependency.
enum NativeDecodoService {
    struct Credentials: Decodable { let username: String; let password: String }

    static func validateDevice(_ device: String, type: String) throws {
        let expected = type == "wifi" ? kSCNetworkInterfaceTypeIEEE80211 : kSCNetworkInterfaceTypeEthernet
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        guard interfaces.contains(where: {
            SCNetworkInterfaceGetBSDName($0) as String? == device
                && SCNetworkInterfaceGetInterfaceType($0) == expected
        }) else { throw ProxyRouteError("物理网卡名称与所选网络类型不一致，请检查此 Mac 的网卡") }
    }

    static func credentials(path: String) throws -> Credentials {
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        guard attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.posixPermissions] as? Int ?? 0) & 0o077 == 0,
              (attrs[.size] as? Int ?? Int.max) < 65536 else { throw ProxyRouteError("凭据文件必须是 0600 普通文件") }
        return try JSONDecoder().decode(Credentials.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    static func configuration(context: VMCommandContext, credentials: Credentials, isp: Bool,
                              city: String, zip: String, interface: String,
                              location: DecodoLocation? = nil, occupied: Set<Int> = []) throws -> NativeDecodoConfiguration {
        let endpoint: VMManualProxy
        if isp {
            let account = credentials.username.hasPrefix("user-") ? credentials.username : "user-" + credentials.username
            endpoint = try DecodoISP.endpoint(name: DecodoISP.name(for: context), template: [
                "server": "isp.decodo.com", "type": "http", "tls": true,
                "username": account, "password": credentials.password
            ], city: city, port: DecodoISP.nextPort(occupied: occupied), location: location)
        } else {
            endpoint = try DecodoProxy(context: context, username: credentials.username, password: credentials.password, zip: zip).proxy
        }
        return NativeDecodoConfiguration(host: endpoint.host, address: "", port: endpoint.port,
            username: endpoint.username, password: endpoint.password, interface: interface)
    }

    static func savedConfiguration(directory: URL) throws -> NativeDecodoConfiguration? {
        let reference = directory.appendingPathComponent("native-proxy-reference.json")
        guard FileManager.default.fileExists(atPath: reference.path) else { return nil }
        let path = try JSONDecoder().decode(String.self, from: Data(contentsOf: reference))
        guard path.hasPrefix("/") else { throw ProxyRouteError("原生代理配置引用无效") }
        return try JSONDecoder().decode(NativeDecodoConfiguration.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    /// Include the current machine so rotation never reuses its previous gateway port.
    static func occupiedPorts(context: VMCommandContext) throws -> Set<Int> {
        var ports = Set<Int>()
        for root in Set(context.isolationRoots + [context.directory.deletingLastPathComponent().path]) {
            for directory in try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil) {
                if let config = try savedConfiguration(directory: directory), config.host == "isp.decodo.com" {
                    ports.insert(config.port)
                }
            }
        }
        return ports
    }

    /// Resolve the gateway without Clash fake-IP DNS. The supplied BSD device is physically bound by curl.
    static func resolve(host: String, device: String) async throws -> String {
        let data = try await curl(arguments: ["--noproxy", "*", "--interface", device,
            "--resolve", "dns.alidns.com:443:223.5.5.5",
            "https://dns.alidns.com/resolve?name=\(host)&type=A"])
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let answers = root?["Answer"] as? [[String: Any]] ?? []
        guard let address = answers.first(where: { $0["type"] as? Int == 1 })?["data"] as? String,
              validAddress(address) else { throw ProxyRouteError("未取得 Decodo 真实网关 IPv4，未修改代理") }
        return address
    }

    static func validAddress(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
            && !value.hasPrefix("198.18.") && !value.hasPrefix("198.19.")
    }

    static func probe(_ config: NativeDecodoConfiguration, device: String) async throws -> IPLocation {
        func escape(_ value: String) -> String {
            value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r")
        }
        let input = "proxy = \"https://\(config.host):\(config.port)\"\nproxy-user = \"\(escape(config.username + ":" + config.password))\"\n"
        let data = try await curl(arguments: ["--interface", device,
            "--resolve", "\(config.host):\(config.port):\(config.address)", "--config", "-",
            "https://ip.decodo.com/json?provider=IPinfo"], input: input)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let ip = (root?["proxy"] as? [String: Any])?["ip"] as? String else { throw ProxyRouteError("代理未返回公网 IP") }
        return try IPLocationLookup.decodeDecodo(data, expectedIP: ip)
    }

    static func save(_ config: NativeDecodoConfiguration, context: VMCommandContext) throws -> URL {
        let id = SHA256.hash(data: Data(context.directory.resolvingSymlinksInPath().path.utf8)).map { String(format: "%02x", $0) }.joined()
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".vphone/native-proxies/\(id)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = dir.appendingPathComponent(UUID().uuidString + ".json")
        let data = try JSONEncoder().encode(config)
        guard FileManager.default.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw ProxyRouteError("无法写入本机代理配置")
        }
        return file
    }

    private static func curl(arguments: [String], input: String = "") async throws -> Data {
        try await Task.detached {
            let process = Process(), stdin = Pipe(), stdout = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = ["--disable", "--silent", "--fail", "--connect-timeout", "8", "--max-time", "20"] + arguments
            process.environment = ProcessInfo.processInfo.environment.filter { !["http_proxy", "https_proxy", "all_proxy", "no_proxy"].contains($0.key.lowercased()) }
            process.standardInput = stdin; process.standardOutput = stdout; process.standardError = FileHandle.nullDevice
            try process.run(); try stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8)); try stdin.fileHandleForWriting.close()
            let data = stdout.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw ProxyRouteError("Decodo 物理网卡直连失败（curl \(process.terminationStatus)），未切换出口") }
            return data
        }.value
    }
}
