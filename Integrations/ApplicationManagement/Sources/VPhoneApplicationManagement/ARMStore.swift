import Foundation

struct DownloadError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
func fail(_ message: String) -> DownloadError { DownloadError(message: message) }

struct Options {
    let app: String, bundle: String, version: String, country: String
    let cookie: String?, output: String?
    let download: Bool, historical: Bool
    let timeout: TimeInterval
    init(_ args: [String], hasSession: Bool = false) throws {
        var values: [String: String] = [:]
        var flags = Set<String>()
        var i = 0
        while i < args.count {
            let key = args[i]
            if ["--download", "--historical"].contains(key) {
                guard flags.insert(key).inserted else { throw fail("重复参数") }
            } else {
                guard ["--app-id", "--bundle-id", "--version", "--country", "--cookie-file", "--output", "--timeout"].contains(key),
                      i + 1 < args.count, values[key] == nil else { throw fail("参数无效；运行 --help") }
                i += 1; values[key] = args[i]
            }
            i += 1
        }
        app = values["--app-id"] ?? ""
        bundle = values["--bundle-id"] ?? ""
        version = values["--version"] ?? ""
        country = values["--country"] ?? "us"
        func matches(_ s: String, _ pattern: String) -> Bool { s.range(of: pattern, options: .regularExpression) != nil }
        guard matches(app, "^[0-9]+$"), matches(bundle, "^[A-Za-z0-9_-]+(\\.[A-Za-z0-9_-]+)+$"),
              matches(version, "^[A-Za-z0-9_.-]+$"), matches(country, "^[a-z]{2}$"),
              let seconds = Double(values["--timeout"] ?? "600"), seconds.isFinite, (3...3600).contains(seconds)
        else { throw fail("需要有效 app-id、bundle-id、version、两位 country；timeout 为 3–3600 秒") }
        timeout = seconds; cookie = values["--cookie-file"]; output = values["--output"]
        download = flags.contains("--download"); historical = flags.contains("--historical")
        if download && ((!hasSession && cookie == nil) || output == nil) { throw fail("下载需要 --cookie-file 和 --output") }
        if let output, !output.hasPrefix("/") || !output.hasSuffix(".ipa") || FileManager.default.fileExists(atPath: output) {
            throw fail("output 必须是尚不存在的绝对 .ipa 路径")
        }
    }
}

// Cookie is explicit and only goes to the supplier origin. Do not follow API redirects.
final class RedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard task.taskDescription == "download", request.url?.scheme == "https" else {
            completionHandler(nil); return
        }
        var clean = request
        if request.url?.host != "armconverter.com" {
            clean.setValue(nil, forHTTPHeaderField: "Cookie")
            clean.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(clean)
    }
}

struct Client {
    let options: Options
    let cookie: String?
    let session: URLSession
    var base: String { "https://armconverter.com/decryptedappstore/download/\(options.app)/\(options.bundle)/\(options.version)" }
    init(_ options: Options, sessionCookie: String? = nil, userAgent: String? = nil) throws {
        self.options = options
        if let sessionCookie {
            guard !sessionCookie.isEmpty, sessionCookie.rangeOfCharacter(from: .newlines) == nil else { throw ARMStoreLoginRequired() }
            cookie = sessionCookie
        } else if let path = options.cookie {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            guard attrs[.type] as? FileAttributeType == .typeRegular,
                  let mode = attrs[.posixPermissions] as? Int, mode & 0o077 == 0,
                  let size = attrs[.size] as? Int, size <= 16384 else { throw fail("Cookie 文件必须是私有普通文件（0600），且小于 16 KiB") }
            let value = try String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.contains("="), !value.contains("\n"), !value.contains("\r") else { throw fail("Cookie 文件应仅包含一行 Cookie 请求头值") }
            cookie = value
        } else { cookie = nil }
        let config = URLSessionConfiguration.ephemeral
        if let userAgent { config.httpAdditionalHeaders = ["User-Agent": userAgent] }
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = options.timeout
        session = URLSession(configuration: config, delegate: RedirectPolicy(), delegateQueue: nil)
    }
    func request(_ url: URL, method: String = "GET") -> URLRequest {
        var r = URLRequest(url: url); r.httpMethod = method
        r.setValue(cookie, forHTTPHeaderField: "Cookie")
        r.setValue("https://armconverter.com/store/\(options.country)/\(options.app)", forHTTPHeaderField: "Referer")
        return r
    }
    func api(_ suffix: String, method: String = "GET") async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request(URL(string: base + suffix)!, method: method))
        guard let http = response as? HTTPURLResponse else { throw fail("接口响应无效") }
        guard http.statusCode != 401 else { throw ARMStoreLoginRequired() }
        guard (200...299).contains(http.statusCode), data.count < 1_048_576,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw fail("接口未返回正常 JSON；可能需要登录、浏览器验证或接口已变化（HTTP \(http.statusCode)）")
        }
        if object["loginRequired"] as? Bool == true { throw ARMStoreLoginRequired() }
        if let error = object["error"] as? String, !error.isEmpty { throw fail("服务端拒绝请求；请在网页查看配额、会员或应用限制") }
        return object
    }
    func run() async throws {
        let deadline = Date().addingTimeInterval(options.timeout)
        var scheduled = false
        while Date() < deadline {
            let info = try await api("/info")
            guard let state = info["state"] as? String else { throw fail("状态字段缺失，接口可能变化") }
            print("state=\(state) available=\(info["available"] as? Bool ?? false) requestable=\(info["requestable"] as? Bool ?? false)")
            if !options.download { return }
            if state == "ready", info["available"] as? Bool == true {
                print("正在获取下载授权…")
                let prepared = try await api("/prepare", method: "POST")
                guard let token = prepared["token"] as? String, !token.isEmpty else { throw fail("未取得下载 token；请检查网页配额") }
                var url = URLComponents(string: base)!
                url.queryItems = [URLQueryItem(name: "token", value: token)]
                print("正在下载并校验 IPA…")
                try await save(url.url!); return
            }
            if !["enqueued", "processing"].contains(state) {
                guard !scheduled, info["requestable"] as? Bool == true else { throw fail("当前版本不可申请，请在网页检查权限或选择其它版本") }
                let result = try await api("/schedule?country=\(options.country)" + (options.historical ? "&hist=true" : ""), method: "POST")
                guard result["success"] as? Bool == true else { throw fail("任务提交失败；未自动重复提交") }
                scheduled = true
            }
            try await Task.sleep(for: .seconds(3))
        }
        throw fail("等待超时；服务器任务可能仍在排队，重新查询状态，不要重复提交")
    }
    func save(_ url: URL) async throws {
        // Use a download task so IPA bytes stream to disk, not memory.
        let result: (URL, URLResponse) = try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: request(url)) { file, response, error in
                if let error { continuation.resume(throwing: error); return }
                guard let file, let response else { continuation.resume(throwing: fail("下载失败")); return }
                let held = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
                do { try FileManager.default.moveItem(at: file, to: held); continuation.resume(returning: (held, response)) }
                catch { continuation.resume(throwing: error) }
            }
            task.taskDescription = "download"; task.resume()
        }
        defer { try? FileManager.default.removeItem(at: result.0) }
        guard (result.1 as? HTTPURLResponse)?.statusCode == 200 else { throw fail("下载响应不是 HTTP 200") }
        let test = Process(); test.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        test.arguments = ["-tqq", result.0.path]; test.standardOutput = FileHandle.nullDevice; test.standardError = FileHandle.nullDevice
        try test.run(); test.waitUntilExit()
        guard test.terminationStatus == 0 else { throw fail("下载内容不是完整 ZIP/IPA，未保存") }
        let listing = Process(), pipe = Pipe()
        listing.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        listing.arguments = ["-Z1", result.0.path]; listing.standardOutput = pipe
        listing.standardError = FileHandle.nullDevice
        try listing.run()
        let entries = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        listing.waitUntilExit()
        let plists = entries.split(separator: "\n").filter { $0.range(of: #"^Payload/[^/]+\.app/Info\.plist$"#, options: .regularExpression) != nil }
        guard listing.terminationStatus == 0, plists.count == 1 else { throw fail("IPA 缺少唯一主应用 Info.plist") }
        let extract = Process(), content = Pipe()
        extract.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        extract.arguments = ["-p", result.0.path, String(plists[0])]
        extract.standardOutput = content; extract.standardError = FileHandle.nullDevice
        try extract.run()
        let data = content.fileHandleForReading.readDataToEndOfFile(); extract.waitUntilExit()
        guard extract.terminationStatus == 0,
              let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["CFBundleIdentifier"] as? String == options.bundle else { throw fail("IPA bundle ID 与请求不匹配") }
        try FileManager.default.moveItem(at: result.0, to: URL(fileURLWithPath: options.output!))
        print("已保存：\(options.output!)；安装前仍需核对 Payload、bundle ID、版本及来源")
    }
}
