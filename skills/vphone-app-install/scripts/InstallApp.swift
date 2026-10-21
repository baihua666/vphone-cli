import Foundation

func emit(_ message: String) {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
}

struct InstallOptions {
    var baseURL: URL
    var tokenFile: URL
    var package: URL
    var launch: Bool

    init(_ arguments: [String]) throws {
        var values = [String: String]()
        var paths = [String]()
        var launch = false
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--launch" {
                launch = true
            } else if ["--api-url", "--token-file"].contains(argument) {
                index += 1
                guard index < arguments.count, values[argument] == nil else {
                    throw failure("缺少或重复参数：\(argument)")
                }
                values[argument] = arguments[index]
            } else if argument.hasPrefix("--") {
                throw failure("未知参数：\(argument)")
            } else {
                paths.append(argument)
            }
            index += 1
        }
        guard let address = values["--api-url"], let url = URL(string: address),
              url.scheme == "http", ["127.0.0.1", "[::1]", "::1"].contains(url.host ?? ""),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              let token = values["--token-file"], paths.count == 1
        else { throw failure("需要本机 HTTP API、token 文件和一个 IPA/TIPA；运行 --help 查看用法") }
        let package = URL(fileURLWithPath: paths[0]).standardizedFileURL
        guard ["ipa", "tipa"].contains(package.pathExtension.lowercased()) else {
            throw failure("安装包必须是 .ipa 或 .tipa")
        }
        // The shared WebSocket client appends an NSString path and needs a leading slash.
        var normalized = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        normalized.path = "/"
        self.baseURL = normalized.url!
        self.tokenFile = URL(fileURLWithPath: token)
        self.package = package
        self.launch = launch
    }
}

func failure(_ message: String) -> NSError {
    NSError(domain: "vphone-app-install", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

func object(_ value: VPhoneJSONValue) throws -> [String: VPhoneJSONValue] {
    guard case let .object(result) = value else { throw failure("API 返回格式错误") }
    return result
}

func installedApp(_ value: VPhoneJSONValue, id: String) throws -> [String: VPhoneJSONValue]? {
    guard case let .array(apps)? = try object(value)["apps"] else { throw failure("apps.list 缺少 apps") }
    return try apps.map(object).first { $0["bundle_id"] == .string(id) }
}

func install(_ client: VPhoneAPIClient, path: String) async throws -> VPhoneJSONValue {
    // Large archives can outlive the existing HTTP client's 130-second RPC deadline.
    let socket = try client.openWebSocket()
    let deadline = Task {
        try await Task.sleep(nanoseconds: 600_000_000_000)
        FileHandle.standardError.write(Data("安装等待超过 10 分钟；关闭本次连接，请先核对客体状态再决定后续操作。\n".utf8))
        await socket.close()
    }
    defer { deadline.cancel() }
    do {
        let id = VPhoneJSONValue.string(UUID().uuidString)
        try await socket.send("apps.install", params: ["path": .string(path), "registration": .string("User")], id: id)
        while true {
            if case let .response(response) = try await socket.next(), response.id == id {
                await socket.close()
                if let error = response.error { throw error }
                guard let result = response.result else { throw failure("安装响应缺少 result") }
                return result
            }
        }
    } catch {
        await socket.close()
        throw error
    }
}

@main
struct InstallApp {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments == ["--help"] || arguments.isEmpty {
                emit("用法：install-app.sh --api-url http://127.0.0.1:18761 --token-file /绝对路径/token [--launch] /绝对路径/App.ipa")
                emit("--launch 安装后启动并观察 20 秒；仍须检查真实界面及关键功能。VM 必须先以 --api-listen 启动。")
                return
            }
            if arguments == ["--self-test"] {
                try selfTest()
                emit("参数校验与安装结果解析检查通过")
                return
            }
            let options = try InstallOptions(arguments)
            let attributes = try FileManager.default.attributesOfItem(atPath: options.package.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.size] as? NSNumber)?.int64Value ?? 0 > 0 else { throw failure("安装包不是非空普通文件") }
            let tokenAttributes = try FileManager.default.attributesOfItem(atPath: options.tokenFile.path)
            guard let mode = tokenAttributes[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0 else {
                throw failure("token 文件权限过宽，请先 chmod 600")
            }
            let token = try String(contentsOf: options.tokenFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            guard (16...256).contains(token.count), token.range(of: "^[A-Za-z0-9._~-]+$", options: .regularExpression) != nil else {
                throw failure("token 格式无效")
            }
            let client = VPhoneAPIClient(baseURL: options.baseURL, token: token)
            emit("检查 guest API…")
            _ = try await client.call("display.auto_lock")
            let directory = "/var/mobile/Documents/vphone-installs"
            _ = try await client.call("files.mkdir", params: ["path": .string(directory)])
            let guestPath = directory + "/" + UUID().uuidString + "." + options.package.pathExtension.lowercased()
            emit("上传 \(options.package.lastPathComponent)…")
            emit("客体临时包：\(guestPath)")
            _ = try await client.uploadFile(from: options.package, toGuestPath: guestPath)
            emit("调用原生 apps.install…")
            let result = try object(await install(client, path: guestPath))
            guard case let .string(id)? = result["bundle_id"], !id.isEmpty else { throw failure("安装结果缺少 bundle_id") }
            let listed = try await client.call("apps.list", params: ["filter": .string("user")])
            guard let app = try installedApp(listed, id: id) else { throw failure("安装后未找到应用：\(id)") }
            let version: String
            if case let .string(value)? = app["version"] { version = value } else { version = "未知" }
            emit("已安装：\(id)，版本 \(version)")
            if options.launch {
                _ = try await client.call("apps.launch", params: ["bundle_id": .string(id)])
                for _ in 0..<4 {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    let running = try await client.call("apps.list", params: ["filter": .string("running")])
                    guard try installedApp(running, id: id) != nil else {
                        throw failure("已安装，但启动后退出：\(id)；检查 logs.crashes，勿自动重装或修改固件")
                    }
                }
                emit("启动后持续运行 20 秒：\(id)；请继续检查界面和实际功能")
            }
        } catch {
            let message = (error as? VPhoneAPIError)?.description ?? error.localizedDescription
            FileHandle.standardError.write(Data("安装检查失败：\(message)\n".utf8))
            exit(1)
        }
    }

    static func selfTest() throws {
        let valid = ["--api-url", "http://127.0.0.1:18761", "--token-file", "/tmp/token", "含 空格.ipa", "--launch"]
        let parsed = try InstallOptions(valid)
        guard parsed.launch, parsed.baseURL.path == "/", parsed.package.lastPathComponent == "含 空格.ipa" else { throw failure("有效参数检查失败") }
        for invalid in [Array(valid.dropLast(2)), valid + ["extra.ipa"], valid + ["--unknown"],
                        ["--api-url", "http://example.com", "--token-file", "/tmp/token", "App.ipa"]] {
            do { _ = try InstallOptions(invalid) } catch { continue }
            throw failure("无效参数被接受：\(invalid)")
        }
        let listed: VPhoneJSONValue = .object(["apps": .array([.object(["bundle_id": .string("test.app")])])])
        guard try installedApp(listed, id: "test.app") != nil,
              try installedApp(listed, id: "absent.app") == nil else { throw failure("应用列表解析检查失败") }
    }
}
