import Foundation
import Yams

enum ClashYAMLScalar {
    static func replacing(in text: String, node: Node, with value: String, flow: Bool = false) throws -> String {
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
            while end < scalars.count, scalars[end] != "\n", scalars[end] != "\r" {
                if flow && [",", "}", "]"].contains(scalars[end]) { break }
                end += 1
            }
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
        let replacement = String(data: try encoder.encode(value), encoding: .utf8)!
        let result = String(String.UnicodeScalarView(scalars[..<offset])) + replacement
            + String(String.UnicodeScalarView(scalars[end...]))
        return result
    }
}
