import Foundation
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION && VPHONE_CUSTOM_THREADS_AUTOMATION
enum ThreadsRestriction {
    static func check(directory: URL) throws {
        let file = directory.appendingPathComponent("retry-after.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let until = try JSONDecoder().decode(Double.self, from: Data(contentsOf: file))
        if Date().timeIntervalSince1970 < until {
            throw Failure("Threads 要求 24 小时后再试；本任务暂停至 \(Date(timeIntervalSince1970: until).formatted())，未提交新操作。")
        }
    }
    static func inspect(_ elements: [[String: Any]], directory: URL) throws {
        guard elements.contains(where: { $0["label"] as? String == "Try again in 24 hours" }) else { return }
        let file = directory.appendingPathComponent("retry-after.json")
        if !FileManager.default.fileExists(atPath: file.path) {
            try JSONEncoder().encode(Date().addingTimeInterval(86400).timeIntervalSince1970).write(to: file, options: .atomic)
        }
        throw Failure("Threads 提示 Try again in 24 hours；已保存暂停时间，未继续提交操作。")
    }
}
#endif
