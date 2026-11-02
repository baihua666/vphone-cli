#if VPHONE_CUSTOM_THREADS_DESKTOP
import Foundation

@MainActor public final class ThreadsStore {
    public let root: URL
    public let credentials: URL
    public private(set) var accounts: [ThreadsAccount] = []
    public private(set) var tasks: [ThreadsTaskRecord] = []
    public init(root: URL, credentials: URL) throws {
        self.root = root; self.credentials = credentials
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        accounts = try read("accounts.json", fallback: [])
        tasks = try read("tasks.json", fallback: [])
        // A UI crash must not erase the engine's durable publish checkpoint.
        for index in tasks.indices where tasks[index].status == "运行中" {
            tasks[index].status = "已中断"; tasks[index].detail = "上次运行中断；重试将沿用原任务核验。"
        }
        try save()
    }
    private func read<T: Decodable>(_ name: String, fallback: T) throws -> T {
        let url = root.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return fallback }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func save() throws {
        try write(accounts, to: root.appendingPathComponent("accounts.json"))
        try write(tasks, to: root.appendingPathComponent("tasks.json"))
    }
    public func saveAccount(username: String, machinePath: String, password: String) throws {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try ThreadsTaskRequest(account: username, socket: machinePath + "/vphone.sock",
                               marker: "VPHONE-00000000", caption: "validate").validate()
        guard !password.contains("\n"), !password.contains("\r") else { throw ThreadsDesktopError("密码不能包含换行") }
        try FileManager.default.createDirectory(at: credentials, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = credentials.appendingPathComponent(username + ".password")
        if !password.isEmpty {
            try Data(password.utf8).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } else if !FileManager.default.fileExists(atPath: file.path) { throw ThreadsDesktopError("请输入密码") }
        let account = ThreadsAccount(username: username, machinePath: machinePath)
        if let index = accounts.firstIndex(where: { $0.id == username }) { accounts[index] = account }
        else { accounts.append(account) }
        try save()
    }
    public func password(for username: String) throws -> String {
        guard accounts.contains(where: { $0.id == username }) else { throw ThreadsDesktopError("账号不存在") }
        return try String(contentsOf: credentials.appendingPathComponent(username + ".password"), encoding: .utf8)
    }
    public func directory(_ id: UUID) -> URL { root.appendingPathComponent("tasks/" + id.uuidString) }
    public func create(account: ThreadsAccount, image: URL, caption: String, freshLogin: Bool, testProfile: Bool) throws -> ThreadsTaskRecord {
        let id = UUID()
        let request = ThreadsTaskRequest(account: account.username, socket: account.machinePath + "/vphone.sock",
            marker: "VPHONE-" + id.uuidString.prefix(8), caption: caption, freshLogin: freshLogin, testProfile: testProfile)
        try request.validate()
        let folder = directory(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            try ThreadsImage.prepare(source: image, marker: request.marker, destination: folder.appendingPathComponent("fixture.png"))
            try write(request, to: folder.appendingPathComponent("request.json"))
            let task = ThreadsTaskRecord(id: id, createdAt: Date(), request: request, status: "待运行", detail: "")
            tasks.insert(task, at: 0); try save(); return task
        } catch {
            tasks.removeAll { $0.id == id }
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
    public func update(_ id: UUID, status: String, detail: String) throws {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { throw ThreadsDesktopError("任务不存在") }
        tasks[index].status = status; tasks[index].detail = detail
        try save()
    }
}

#endif
