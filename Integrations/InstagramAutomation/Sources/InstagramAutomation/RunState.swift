import Foundation
import Darwin
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION
struct RunState: Codable {
    let socket: String
    let account: String
    var marker: String
    let freshLogin: Bool
    var passwordLogin: Bool? = nil
    var platform: String? = nil
    var completed: [String] = []
    var loginSubmitted = false
    var publishAttempted = false
    var originalBio: String? = nil
    var bioChanged = false
    func validate(socket: String, account: String, freshLogin: Bool, passwordLogin: Bool = false, platform: String = "instagram") throws {
        guard self.socket == socket, self.account == account, self.freshLogin == freshLogin,
              (self.passwordLogin ?? false) == passwordLogin, (self.platform ?? "instagram") == platform else {
            throw Failure("运行目录绑定的实例、账号或登录模式不同")
        }
    }
}
final class RunJournal {
    let directory: URL
    var state: RunState
    private let handle: FileHandle
    private let lock: FileHandle
    init(directory: URL, socket: String, account: String, freshLogin: Bool, passwordLogin: Bool = false, platform: String = "instagram") throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let fd = open(socket + ".instagram-test.lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Failure("无法建立实例锁") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); throw Failure("实例已有任务") }
        lock = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let stateURL = directory.appendingPathComponent("state.json")
        if FileManager.default.fileExists(atPath: stateURL.path) {
            state = try JSONDecoder().decode(RunState.self, from: Data(contentsOf: stateURL))
            try state.validate(socket: socket, account: account, freshLogin: freshLogin, passwordLogin: passwordLogin, platform: platform)
        } else {
            state = RunState(socket: socket, account: account,
                             marker: "VPHONE-" + UUID().uuidString.prefix(8).uppercased(), freshLogin: freshLogin,
                             passwordLogin: passwordLogin, platform: platform)
        }
        let report = open(directory.appendingPathComponent("events.jsonl").path,
                          O_CREAT | O_APPEND | O_WRONLY | O_NOFOLLOW, 0o600)
        guard report >= 0 else { throw Failure("报告不可写") }
        handle = FileHandle(fileDescriptor: report, closeOnDealloc: true)
        try save()
    }
    func save() throws {
        let url = directory.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw Failure("无法持久化进度") }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw Failure("无法同步进度") }
    }
    func event(_ stage: String, _ status: String) throws {
        var data = try JSONSerialization.data(withJSONObject: ["step": stage, "status": status,
            "time": ISO8601DateFormatter().string(from: Date())])
        data.append(10)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        print("\(stage): \(status)")
        fflush(stdout)
    }
    func stage(_ name: String, operation: () throws -> Void) throws {
        if state.completed.contains(name) { return }
        try event(name, "started")
        do {
            try operation()
            state.completed.append(name)
            try save()
            try event(name, "passed")
        } catch {
            try event(name, "stopped")
            throw error
        }
    }
    func checkpoint() throws {
        guard !state.publishAttempted else { throw Failure("已有发布尝试，只允许核验") }
        state.publishAttempted = true
        try save()
    }
}
#endif
