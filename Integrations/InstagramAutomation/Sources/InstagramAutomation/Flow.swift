import Foundation
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION
struct Flow: Codable {
    let steps: [Step]
    struct Step: Codable {
        let id: String
        let action: String
        var text: String? = nil
        var identifier: String? = nil
        var secretAccount: String? = nil
        var delayMs: Int? = nil
    }
    func validate() throws {
        guard !steps.isEmpty, Set(steps.map(\.id)).count == steps.count,
              steps.allSatisfy({ !$0.id.isEmpty }) else { throw Failure("步骤为空或 ID 重复") }
        let allowed = ["launch", "wait", "tap", "type", "secret", "publish", "clear", "waitGone", "visualWait", "visualTap", "visualPublish"]
        for step in steps {
            if let delay = step.delayMs, !(0...1000).contains(delay) { throw Failure("输入延迟需为 0–1000 毫秒") }
            guard allowed.contains(step.action) else { throw Failure("未知步骤类型") }
            if ["wait", "waitGone", "tap", "publish"].contains(step.action) {
                guard step.text?.isEmpty == false || step.identifier?.isEmpty == false else {
                    throw Failure("元素选择器不能为空")
                }
            }
            if step.action.hasPrefix("visual"), step.text?.isEmpty != false { throw Failure("视觉步骤需要文字") }
            if step.action == "type", step.text == nil { throw Failure("缺少输入文字") }
            if step.action == "secret", step.secretAccount?.isEmpty != false { throw Failure("缺少钥匙串账号引用") }
        }
        if let index = steps.firstIndex(where: { ["publish", "visualPublish"].contains($0.action) }) {
            guard steps.filter({ ["publish", "visualPublish"].contains($0.action) }).count == 1,
                  steps.suffix(from: index + 1).contains(where: { ["wait", "visualWait"].contains($0.action) }) else {
                throw Failure("发布后必须有结果断言，且只允许一次发布")
            }
        }
    }
}
struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
struct Runner {
    var rpc: (String, [String: Any]) throws -> Void
    var secret: (String) throws -> String
    var checkpoint: () throws -> Void
    var report: (String, String) throws -> Void

    func run(_ flow: Flow) throws {
        try flow.validate()
        for step in flow.steps {
            try report(step.id, "started")
            do {
                var selector: [String: Any] = ["match": "exact", "timeout": 20]
                if let text = step.text { selector["text"] = text }
                if let identifier = step.identifier { selector["identifier"] = identifier }
                switch step.action {
                case "visualWait", "visualTap", "visualPublish":
                    try rpc("host.visual.wait", ["text": step.text!])
                    if step.action == "visualPublish" { try checkpoint() }
                    if step.action != "visualWait" { try rpc("host.visual.tap", ["text": step.text!]) }
                case "launch": try rpc("apps.launch", ["bundle_id": "com.burbn.instagram"])
                case "wait": try rpc("ui.wait", selector)
                case "waitGone": try rpc("ui.wait_gone", selector)
                case "tap", "publish":
                    try rpc("ui.wait", selector)
                    if step.action == "publish" { try checkpoint() }
                    try rpc("ui.tap_element", selector)
                case "clear":
                    try rpc("input.key", ["name": "cmd+a"])
                    try rpc("input.key", ["name": "backspace"])
                case "type":
                    var params: [String: Any] = ["text": step.text!]
                    if let delay = step.delayMs { params["delay_ms"] = delay }
                    try rpc("input.type", params)
                case "secret": try rpc("input.type", ["text": try secret(step.secretAccount!)])
                default: throw Failure("未知步骤类型")
                }
                try report(step.id, "passed")
            } catch {
                try report(step.id, "failed")
                // Do not print transport errors: a guest may echo credentials.
                throw Failure("步骤 \(step.id) 失败；停止执行，未自动重试")
            }
        }
    }
}
#endif
