import Foundation
import ThreadsDesktop
import Darwin
import PhotoPicker
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION
func main() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.count == 4, args[0] == "photo-verify" {
        guard PhotoPicker.isEnabled else { throw Failure("通用照片选择未编译启用") }
        let socket = GuestSocket(path: args[1])
        try PhotoPicker(rpc: socket.request).verify(image: URL(fileURLWithPath: args[2]), identifier: args[3])
        print("单个图片视图与原图匹配；只读核验，未发布")
        return
    }
    if args.count == 3, args[0] == "photo-select" {
        guard PhotoPicker.isEnabled else { throw Failure("通用照片选择未编译启用") }
        let lock = open(args[1] + ".instagram-test.lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { throw Failure("无法建立实例锁") }
        defer { close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw Failure("实例已有任务") }
        try PhotoPicker(rpc: GuestSocket(path: args[1]).request).select(image: URL(fileURLWithPath: args[2]))
        print("照片格子已选择；未点击完成、未输入文案、未发布")
        return
    }
#if VPHONE_CUSTOM_THREADS_AUTOMATION
if args.count == 2, args[0] == "threads-photo-check" {
    let directory = URL(fileURLWithPath: args[1])
    let request = try JSONDecoder().decode(ThreadsTaskRequest.self, from: Data(contentsOf: directory.appendingPathComponent("request.json")))
    try request.validate()
    guard let name = request.sourceImageName, request.includesImage else { throw Failure("此任务没有可验证的原图") }
    guard PhotoPicker.isEnabled else { throw Failure("通用照片选择未编译启用") }
    let lock = open(request.socket + ".instagram-test.lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    guard lock >= 0 else { throw Failure("无法建立实例锁") }
    defer { close(lock) }
    guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw Failure("实例已有任务") }
    try ThreadsPhotoValidation(ui: Screen(socket: GuestSocket(path: request.socket)), image: directory.appendingPathComponent(name)).run()
    return
}
if args.count == 2, args[0] == "threads-task" {
    let directory = URL(fileURLWithPath: args[1])
    let request = try JSONDecoder().decode(ThreadsTaskRequest.self, from: Data(contentsOf: directory.appendingPathComponent("request.json")))
    try request.validate()
    try ThreadsWorkflow.run(socket: request.socket, directory: directory,
                            freshLogin: request.freshLogin, password: nil, request: request)
    return
}
#endif
if args.first == "threads-e2e" {

        #if VPHONE_CUSTOM_THREADS_AUTOMATION
        guard args.count >= 3, args.dropFirst(3).allSatisfy({ ["--fresh-login", "--password-stdin"].contains($0) }) else {
            throw Failure("用法: threads-e2e SOCKET RUN_DIRECTORY [--fresh-login] [--password-stdin]")
        }
        let password = try args.contains("--password-stdin") ? Credentials.hiddenInput("密码: ") : nil
        try ThreadsWorkflow.run(socket: args[1], directory: URL(fileURLWithPath: args[2]),
                                freshLogin: args.contains("--fresh-login"), password: password)
        return
        #else
        throw Failure("Threads 自动化未编译启用")
        #endif
    }
    if args.count == 4, args[0] == "import-fixture" {
        guard args[2].range(of: "^VPHONE-[A-Z0-9-]{1,64}$", options: .regularExpression) != nil else {
            throw Failure("测试图片编号格式无效")
        }
        let fd = open(args[1] + ".instagram-test.lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Failure("无法建立实例锁") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw Failure("实例已有任务") }
        let image = URL(fileURLWithPath: args[3])
        try Fixture.create(marker: args[2], at: image)
        try MediaImport(ui: Screen(socket: GuestSocket(path: args[1]))).run(image: image, marker: args[2])
        print("测试图片已导入相册")
        return
    }
    if args.count >= 3, args[0] == "e2e" {
        guard args.dropFirst(3).allSatisfy({ ["--fresh-login", "--password-login", "--password-stdin"].contains($0) }),
              !(args.contains("--fresh-login") && args.contains("--password-login")) else { throw Failure("未知参数或互斥的登录模式") }
        let password = try args.contains("--password-stdin") ? Credentials.hiddenInput("密码（仅从标准输入读取）: ") : nil
        try Workflow.run(socket: args[1], directory: URL(fileURLWithPath: args[2]),
                         freshLogin: args.contains("--fresh-login"), password: password, passwordLogin: args.contains("--password-login"))
        return
    }
    if args.count == 2, args[0] == "set-password" { try Credentials.store(args[1]); return }
    if args.count == 3, args[0] == "fixture" {
        try Fixture.create(marker: args[1], at: URL(fileURLWithPath: args[2])); return
    }
    guard args.count == 2 || args.count == 4, ["validate", "run"].contains(args[0]) else {
        throw Failure("用法: instagram-test validate FLOW.json | run FLOW.json SOCKET RUN-DIRECTORY")
    }
    let flow = try JSONDecoder().decode(Flow.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
    try flow.validate()
    if args[0] == "validate" { print("配置校验通过（未执行）"); return }
    guard args.count == 4 else { throw Failure("缺少 socket 或运行目录") }
    let socket = GuestSocket(path: args[2])
    let directory = URL(fileURLWithPath: args[3], isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let lock = open((args[2] + ".instagram-test.lock"), O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    guard lock >= 0 else { throw Failure("无法建立实例锁") }
    defer { close(lock) }
    guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw Failure("该实例已有自动化任务") }
    let marker = directory.appendingPathComponent("publish-attempted")
    guard !FileManager.default.fileExists(atPath: marker.path) else {
        throw Failure("此运行已有发布尝试；请人工核对帖子，禁止自动重复发布")
    }
    let reportURL = directory.appendingPathComponent("events.jsonl")
    let reportFD = open(reportURL.path, O_CREAT | O_APPEND | O_WRONLY | O_NOFOLLOW, 0o600)
    guard reportFD >= 0 else { throw Failure("无法创建报告") }
    let handle = FileHandle(fileDescriptor: reportFD, closeOnDealloc: true)
    let visual = VisualControl(socket: socket)
    let runner = Runner(rpc: { method, params in
        if method.hasPrefix("host.visual.") {
            try visual.perform(text: params["text"] as! String, tap: method.hasSuffix("tap"))
        } else { try socket.call(method, params) }
    }, secret: Credentials.read, checkpoint: {
        let fd = open(marker.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Failure("已有发布尝试") }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw Failure("无法持久化发布记录") }
    }, report: { id, status in
        var data = try JSONSerialization.data(withJSONObject: ["step": id, "status": status,
            "time": ISO8601DateFormatter().string(from: Date())])
        data.append(10)
        try handle.write(contentsOf: data)
        try handle.synchronize()
    })
    try runner.run(flow)
    print("所有步骤通过；报告: \(reportURL.path)")
}
do { try main() } catch is VerificationRequired {
    exit(22)
} catch {
    let message = (error as? Failure)?.description ?? (error as? PhotoPickerError)?.message ?? "配置、传输或文件操作失败"
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
#else
FileHandle.standardError.write(Data("Instagram 自动化未编译启用\n".utf8))
exit(1)
#endif
