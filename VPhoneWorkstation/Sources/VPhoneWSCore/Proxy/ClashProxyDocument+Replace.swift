import Foundation
import Yams

extension ClashProxyDocument {
    func configuration(named name: String, key: String) throws -> [String: Any]? {
        guard let root = try Yams.compose(yaml: text), let mapping = root.mapping,
              mapping.filter({ $0.key.string == key }).count <= 1 else { throw ProxyRouteError("代理列表字段重复或无效") }
        guard root[key] != nil else { return nil }
        guard let sequence = root[key]?.sequence, sequence.anchor == nil,
              sequence.allSatisfy({ $0.mapping != nil }),
              let loaded = try Yams.load(yaml: text) as? [String: Any], let nodes = loaded[key] as? [[String: Any]] else {
            throw ProxyRouteError("代理列表必须是普通 YAML 数组")
        }
        let matches = nodes.filter { $0["name"] as? String == name }
        guard matches.count <= 1 else { throw ProxyRouteError("代理名称重复，未修改配置") }
        return matches.first
    }

    /// Only credentials change for a managed endpoint; preserve unrelated nodes and comments.
    func replacing(_ proxy: VMManualProxy, key: String, expected: [String: Any]) throws -> String {
        guard let current = try configuration(named: proxy.name, key: key),
              NSDictionary(dictionary: current) == NSDictionary(dictionary: expected) else {
            throw ProxyRouteError("代理配置已改变，请刷新后重试")
        }
        var expectedRoot = try Yams.load(yaml: text) as! [String: Any]
        var result = text
        var fields = current
        // A locally configured transit reaches the supplier gateway; rotating its session
        // must retain that transport without allowing arbitrary endpoint changes.
        var replacementConfiguration = proxy.configuration
        if let dialer = current["dialer-proxy"] as? String, !dialer.isEmpty, dialer != proxy.name {
            replacementConfiguration["dialer-proxy"] = dialer
        }
        let changedFields = proxy.host == "isp.decodo.com" ? ["username", "password", "port"] : ["username", "password"]
        for key in changedFields { fields[key] = proxy.configuration[key] }
        guard NSDictionary(dictionary: fields) == NSDictionary(dictionary: replacementConfiguration) else {
            throw ProxyRouteError("此入口只允许更新专属节点的认证与会话参数")
        }
        for field in changedFields {
            let root = try Yams.compose(yaml: result)!
            guard let node = root[key]?.sequence?.first(where: { $0["name"]?.string == proxy.name }),
                  let mapping = node.mapping, mapping.anchor == nil,
                  mapping.filter({ $0.key.string == field }).count == 1,
                  let scalar = node[field], let replacementValue = proxy.configuration[field] else {
                throw ProxyRouteError("代理认证字段重复或无效")
            }
            let replacement = String(describing: replacementValue)
            guard let mark = node.mark else { throw ProxyRouteError("代理节点缺少源码位置") }
            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            let offset = lines.prefix(mark.line - 1).reduce(0) { $0 + $1.unicodeScalars.count + 1 } + mark.column - 1
            // Like sequence styles, Yams reads mapping.style from the end event.
            let flow = Array(result.unicodeScalars)[offset] == "{"
            result = try ClashYAMLScalar.replacing(in: result, node: scalar, with: replacement, flow: flow, integer: field == "port")
        }
        expectedRoot[key] = (expectedRoot[key] as! [[String: Any]]).map { $0["name"] as? String == proxy.name ? replacementConfiguration : $0 }
        guard let actual = try Yams.load(yaml: result) as? [String: Any],
              NSDictionary(dictionary: actual) == NSDictionary(dictionary: expectedRoot) else {
            throw ProxyRouteError("代理替换核对失败；未修改文件")
        }
        return result
    }
}
