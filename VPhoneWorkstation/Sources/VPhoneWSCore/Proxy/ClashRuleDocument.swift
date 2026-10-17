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
        guard let mark = node.mark, let expected = node.string else { throw ProxyRouteError("规则缺少源码位置") }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let offset = lines.prefix(mark.line - 1).reduce(0) { $0 + $1.unicodeScalars.count + 1 } + mark.column - 1
        let scalars = Array(text.unicodeScalars)
        guard offset >= 0, offset < scalars.count else { throw ProxyRouteError("规则位置无效") }
        var end = offset
        if scalars[offset] == "\"" || scalars[offset] == "'" {
            let quote = scalars[offset]
            end += 1
            while end < scalars.count {
                if quote == "\"", scalars[end] == "\\" { end += 2; continue }
                if scalars[end] == quote {
                    if quote == "'", end + 1 < scalars.count, scalars[end + 1] == quote { end += 2; continue }
                    end += 1
                    break
                }
                end += 1
            }
        } else {
            while end < scalars.count, scalars[end] != "\n", scalars[end] != "\r" { end += 1 }
            // Plain single-line rules only. Leave an inline comment intact.
            if let comment = String(String.UnicodeScalarView(scalars[offset..<end])).range(of: " #") {
                end = offset + String(String.UnicodeScalarView(scalars[offset..<end]))[..<comment.lowerBound].unicodeScalars.count
            }
            while end > offset, scalars[end - 1] == " " { end -= 1 }
        }
        guard end <= scalars.count,
              (try Yams.load(yaml: String(String.UnicodeScalarView(scalars[offset..<end]))) as? String) == expected else {
            throw ProxyRouteError("不支持该规则的 YAML 样式；未修改文件")
        }
        // Go yaml (Mihomo) rejects JSON's optional \/ escape, although libyaml accepts it.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let replacement = String(data: try encoder.encode("PROCESS-PATH,\(process),\(target)"), encoding: .utf8)!
        let result = String(String.UnicodeScalarView(scalars[..<offset])) + replacement
            + String(String.UnicodeScalarView(scalars[end...]))
        guard try ClashRuleDocument(text: result, key: key, process: process).target() == target else {
            throw ProxyRouteError("规则替换验证失败")
        }
        return result
    }
}
