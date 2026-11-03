import Foundation
import Vision
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION
struct Screen {
    let socket: GuestSocket
    var inspect: (([[String: Any]]) throws -> Void)? = nil
    // Only repeat this read-only snapshot, never credential submission or publish taps.
    static func readTree(read: () throws -> [[String: Any]], pause: () -> Void = { Thread.sleep(forTimeInterval: 1) }) throws -> [[String: Any]] {
        for attempt in 0..<10 {
            do { return try read() }
            catch {
                // iOS share sheets can temporarily lose their AX root during transitions.
                let transientAX = ["AX element query failed (-25216)", "AX element query failed (-25215)"].contains { String(describing: error).contains($0) }
                guard attempt < (transientAX ? 9 : 2) else { throw error }
                pause()
            }
        }
        preconditionFailure("unreachable")
    }
    func tree() throws -> [[String: Any]] {
        let elements = try Self.readTree {
            let result = try socket.request("ui.tree", ["limit": 300])
            guard let elements = result["elements"] as? [[String: Any]] else { throw Failure("ui.tree 响应缺少 elements") }
            return elements
        }
        try inspect?(elements)
        return elements
    }
    func has(_ text: String = "", id: String = "") throws -> Bool {
        try tree().contains { element in
            (!text.isEmpty && element["label"] as? String == text) ||
            (!id.isEmpty && element["identifier"] as? String == id)
        }
    }
    func wait(_ text: String = "", id: String = "", tap: Bool = false, index: Int = 0) throws {
        var params: [String: Any] = ["match": "exact", "timeout": 1, "index": index]
        if !text.isEmpty { params["text"] = text }
        if !id.isEmpty { params["identifier"] = id }
        let deadline = Date().addingTimeInterval(90)
        while true {
            do { try socket.call("ui.wait", params); break }
            catch {
                if inspect != nil { _ = try tree() }
                guard Date() < deadline else { throw Failure("等待界面元素超时: \(id.isEmpty ? text : id)") }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        if tap {
            try socket.call("ui.tap_element", params)
            Thread.sleep(forTimeInterval: 0.6)
        }
    }
    func clearAndType(_ text: String) throws {
        try socket.call("input.key", ["name": "cmd+a"])
        try socket.call("input.key", ["name": "backspace"])
        if !text.isEmpty { try socket.call("input.type", ["text": text]) }
    }
    func image() throws -> Data {
        let result = try socket.request("screen.screenshot", [:])
        guard let encoded = result["data"] as? String, let data = Data(base64Encoded: encoded) else {
            throw Failure("截图失败")
        }
        return data
    }
    func words() throws -> [(String, CGRect)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(data: image()).perform([request])
        return (request.results ?? []).compactMap { item in
            item.topCandidates(1).first.map { ($0.string, item.boundingBox) }
        }
    }
    func visual(_ text: String, tap: Bool = false) throws {
        try VisualControl(socket: socket).perform(text: text, tap: tap)
    }
    func codes() throws -> [(String, CGRect)] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(data: image()).perform([request])
        return (request.results ?? []).compactMap { item in
            item.payloadStringValue.map { ($0, item.boundingBox) }
        }
    }
    func markerMatches(_ marker: String) throws -> [(String, CGRect)] {
        let codes = try codes().filter { $0.0 == marker }
        return codes.isEmpty ? try words().filter { $0.0 == marker } : codes
    }
    func waitMarker(_ marker: String) throws {
        for _ in 0..<90 {
            let matches = try markerMatches(marker)
            if matches.count == 1 { return }
            guard matches.isEmpty else { throw Failure("测试图片编号不唯一") }
            Thread.sleep(forTimeInterval: 1)
        }
        throw Failure("等待测试图片编号超时")
    }
    // Only calibrated fallbacks with an immediately checked page guard may use this.
    func point(_ x: Double, _ y: Double) throws {
        let screen = try socket.request("device.screen", [:])
        guard screen["width"] as? Int == 430, screen["height"] as? Int == 932,
              screen["orientation"] as? Int == 0 else { throw Failure("此页面坐标仅校准了 430×932 竖屏") }
        try socket.call("input.tap", ["x": x, "y": y])
    }
    func swipeUp() throws {
        try socket.call("input.swipe", ["x1": 215, "y1": 760, "x2": 215, "y2": 280, "seconds": 0.4])
    }
}
#endif
