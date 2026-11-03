#if VPHONE_CUSTOM_THREADS_DESKTOP
import Foundation
import Observation

@MainActor @Observable public final class ThreadsDesktopModel {
    public private(set) var accounts: [ThreadsAccount] = []
    public private(set) var tasks: [ThreadsTaskRecord] = []
    public private(set) var running: UUID?
    public private(set) var progress = ""
    public var error = ""
    private var store: ThreadsStore?
    private var process: Process?
    public init(root: URL? = nil, credentials: URL? = nil) {
        do {
            store = try ThreadsStore(root: root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("vphone-launchpad/Threads"), credentials: credentials ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/vphone-social-tests"))
            reload()
        } catch { self.error = "本地数据读取失败，未覆盖原文件：" + error.localizedDescription }
    }
    private func reload() { accounts = store?.accounts ?? []; tasks = store?.tasks ?? [] }
    public func saveAccount(username: String, machinePath: String, password: String) {
        do { guard let store else { throw ThreadsDesktopError("存储不可用") }
            try store.saveAccount(username: username, machinePath: machinePath, password: password); reload(); error = ""
        } catch { self.error = error.localizedDescription }
    }
    public func create(account: ThreadsAccount, image: URL?, caption: String, freshLogin: Bool, testProfile: Bool) -> UUID? {
        do { guard let store else { throw ThreadsDesktopError("存储不可用") }
            let task = try store.create(account: account, image: image, caption: caption, freshLogin: freshLogin, testProfile: testProfile)
            reload(); error = ""; return task.id
        } catch { self.error = error.localizedDescription; return nil }
    }
    public func directory(_ id: UUID) -> URL? { store?.directory(id) }
    public func run(_ id: UUID, executable: URL) {
        guard running == nil, let store, tasks.contains(where: { $0.id == id }) else { return }
        let directory = store.directory(id)
        do {
            guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw ThreadsDesktopError("自动化执行器缺失，请安装包含 Threads 功能的 Launchpad") }
            let task = Process()
            task.executableURL = executable
            task.arguments = ["threads-task", directory.path]
            let output = directory.appendingPathComponent("run.log")
            FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let handle = try FileHandle(forWritingTo: output)
            task.standardOutput = handle; task.standardError = handle
            task.standardInput = FileHandle.nullDevice
            try store.update(id, status: "运行中", detail: "正在连接虚拟机")
            running = id; progress = "正在连接虚拟机"; reload()
            try task.run()
            process = task
            Task { [self] in
                while task.isRunning {
                    progress = (try? String(contentsOf: output, encoding: .utf8)) ?? progress
                    try? await Task.sleep(for: .milliseconds(500))
                }
                try? handle.close()
                progress = (try? String(contentsOf: output, encoding: .utf8)) ?? progress
                let stateURL = directory.appendingPathComponent("state.json")
                let state = (try? Data(contentsOf: stateURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                let verified = (state?["completed"] as? [String] ?? []).contains("verify")
                let limited = FileManager.default.fileExists(atPath: directory.appendingPathComponent("retry-after.json").path)
                let attempted = state?["publishAttempted"] as? Bool ?? false
                let status = verified ? "已完成" : limited ? "平台限流" : task.terminationStatus == 22 ? (attempted ? "发布结果待核验" : "等待验证")
                    : attempted ? "发布结果待核验" : "失败（未提交发布）"
                do { try store.update(id, status: status, detail: progress); reload() }
                catch { self.error = "任务结果保存失败：" + error.localizedDescription }
                running = nil; process = nil
            }
        } catch {
            running = nil; process = nil; self.error = error.localizedDescription
            try? store.update(id, status: "失败", detail: error.localizedDescription); reload()
        }
    }
}

#endif
