import Foundation
import CryptoKit
import ThreadsDesktop
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION && VPHONE_CUSTOM_THREADS_AUTOMATION
enum ThreadsTaskBinding {
    struct Binding: Codable, Equatable {
        let request: ThreadsTaskRequest
        let imageHash: String
    }
    static func bind(_ request: ThreadsTaskRequest, journal: RunJournal) throws {
        let directory = journal.directory
        let data = request.includesImage ? try Data(contentsOf: directory.appendingPathComponent("fixture.png")) : nil
        let binding = Binding(request: request, imageHash: data.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "")
        let url = directory.appendingPathComponent("bound-request.json")
        if FileManager.default.fileExists(atPath: url.path) {
            guard try JSONDecoder().decode(Binding.self, from: Data(contentsOf: url)) == binding else {
                throw Failure("任务参数或图片已改变，禁止沿用原任务发布")
            }
        } else {
            guard journal.state.completed.isEmpty && !journal.state.publishAttempted else { throw Failure("不可将既有测试目录转换为发帖任务") }
            try JSONEncoder().encode(binding).write(to: url, options: .atomic)
        }
        journal.state.marker = request.marker
        try journal.save()
    }
}
#endif
