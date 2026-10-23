import Foundation
import Yams

/// Existing purchased ISP endpoints; this does not purchase or provision addresses.
enum ISPProxyPool {
    static func names(runtime: String) throws -> [String] {
        let root = try Yams.load(yaml: runtime) as? [String: Any]
        let nodes = root?["proxies"] as? [[String: Any]] ?? []
        return nodes.compactMap { node -> String? in
            guard (node["server"] as? String)?.lowercased() == "isp.decodo.com",
                  let port = node["port"] as? Int, (10001...63000).contains(port),
                  ["http", "socks5"].contains(node["type"] as? String ?? "") else { return nil }
            return node["name"] as? String
        }.sorted()
    }

}
