import Foundation
import Yams

struct ProxyRouteError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Edit only one existing scalar, preserving every byte outside that scalar.
/// Unsupported YAML styles fail closed instead of reserializing a user's document.
struct ClashRuleDocument {
    let text: String
    let key: String
    let process: String

    func entry() throws -> Node {
        guard !process.contains(","), let root = try Yams.compose(yaml: text),
              let sequence = root[key]?.sequence else {
            throw ProxyRouteError("Clash 规则格式不受支持")
        }
        let matches = sequence.filter { $0.string?.hasPrefix("PROCESS-PATH,\(process),") == true }
        guard matches.count == 1, let node = matches.first,
              node.string?.split(separator: ",", omittingEmptySubsequences: false).count == 3 else {
            throw ProxyRouteError("需要且只能有一条此实例的 PROCESS-PATH 规则；请先在 Clash 中配置独立运行路径")
        }
        return node
    }

    func target() throws -> String { String(try entry().string!.split(separator: ",").last!) }

    func replacing(target: String) throws -> String {
        guard !target.isEmpty, !target.contains(","), !target.contains(where: { $0.isNewline }) else {
            throw ProxyRouteError("节点名称不能包含逗号或换行")
        }
        let node = try entry()
        let result = try ClashYAMLScalar.replacing(in: text, node: node, with: "PROCESS-PATH,\(process),\(target)")
        guard try ClashRuleDocument(text: result, key: key, process: process).target() == target else {
            throw ProxyRouteError("规则替换验证失败")
        }
        return result
    }
}
