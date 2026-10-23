import Foundation

struct WorkflowError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
func reject(_ message: String) -> WorkflowError { WorkflowError(message: message) }

struct InstallConfiguration: Codable {
    struct Source: Codable {
        var appID: String
        var bundleID: String
        var version: String
        var packageVersion: String?
        var country: String?
        var cookieFile: String?
        var chromeProfile: String?
    }
    struct Target: Codable {
        var name: String
        var apiURL: String
        var tokenFile: String
    }
    var ipa: String
    var source: Source
    var targets: [Target]
    var launch: Bool?

    func validate() throws {
        guard ipa.hasPrefix("/"), ipa.hasSuffix(".ipa"), !targets.isEmpty,
              !source.bundleID.isEmpty, !source.version.isEmpty,
              source.cookieFile == nil || source.cookieFile!.hasPrefix("/") else {
            throw reject("配置需要绝对 IPA/Cookie 路径、应用版本、bundle ID 和至少一台机器")
        }
        if let profile = source.chromeProfile {
            guard profile.hasPrefix("/"), source.cookieFile != nil else { throw reject("chromeProfile 必须是绝对路径，并配置私有 cookieFile 缓存") }
        }
        var names = Set<String>(), endpoints = Set<String>()
        for target in targets {
            guard !target.name.isEmpty, names.insert(target.name).inserted,
                  target.tokenFile.hasPrefix("/"), let url = URLComponents(string: target.apiURL),
                  url.scheme == "http", ["127.0.0.1", "[::1]", "::1"].contains(url.host ?? ""),
                  let port = url.port, (1...65535).contains(port),
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  url.path.isEmpty || url.path == "/",
                  endpoints.insert("\(url.host!):\(port)").inserted else {
                throw reject("机器名/端点不可重复；API 必须是带端口的本机 HTTP 地址，token 为绝对路径")
            }
        }
    }
}

func privateFile(_ path: String) throws -> Data {
    let attrs = try FileManager.default.attributesOfItem(atPath: path)
    guard attrs[.type] as? FileAttributeType == .typeRegular,
          let mode = attrs[.posixPermissions] as? Int, mode & 0o077 == 0 else {
        throw reject("配置和凭据必须是私有普通文件（chmod 600）")
    }
    return try Data(contentsOf: URL(fileURLWithPath: path))
}

func run(_ executable: String, _ arguments: [String], capture: Bool = false) throws -> Data {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if capture { process.standardOutput = pipe; process.standardError = FileHandle.nullDevice }
    try process.run()
    let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw reject("子步骤失败，已停止；不会自动重复安装") }
    return data
}

func verifyIPA(_ config: InstallConfiguration) throws {
    _ = try run("/usr/bin/unzip", ["-tqq", config.ipa], capture: true)
    let entries = String(decoding: try run("/usr/bin/unzip", ["-Z1", config.ipa], capture: true), as: UTF8.self)
    let plists = entries.split(separator: "\n").filter { $0.range(of: #"^Payload/[^/]+\.app/Info\.plist$"#, options: .regularExpression) != nil }
    guard plists.count == 1 else { throw reject("IPA 缺少唯一主应用") }
    let data = try run("/usr/bin/unzip", ["-p", config.ipa, String(plists[0])], capture: true)
    guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          plist["CFBundleIdentifier"] as? String == config.source.bundleID,
          plist["CFBundleShortVersionString"] as? String == (config.source.packageVersion ?? config.source.version) else {
        throw reject("IPA 的 bundle ID 或版本与配置不符；未安装")
    }
}

@main struct InstallWorkflow {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--help"] || args.isEmpty {
            print("install-workflow.sh --config /private/install.json [--check]\n复用本地 IPA；缺少时使用配置中的 ARM Store Cookie 下载。--check 仅校验配置、凭据与现有 IPA。")
            return
        }
        do {
            if args == ["--self-test"] { try workflowTests(); print("Workflow tests passed"); return }
            guard args.count == 2 || args.count == 3, args[0] == "--config",
                  args.count == 2 || args[2] == "--check" else { throw reject("参数无效；运行 --help") }
            let config = try JSONDecoder().decode(InstallConfiguration.self, from: privateFile(args[1]))
            try config.validate()
            // Validate every target before any download or install changes state.
            for target in config.targets {
                let token = String(decoding: try privateFile(target.tokenFile), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                guard token.range(of: "^[A-Za-z0-9._~-]{16,256}$", options: .regularExpression) != nil else { throw reject("API token 格式无效") }
            }
            if let cookie = config.source.cookieFile, FileManager.default.fileExists(atPath: cookie) { _ = try privateFile(cookie) }
            let exists = FileManager.default.fileExists(atPath: config.ipa)
            if exists { try verifyIPA(config) }
            if args.last == "--check" { print("配置校验通过；IPA \(exists ? "已核对" : "尚未下载")；未联网或安装"); return }
            guard let scripts = ProcessInfo.processInfo.environment["VPHONE_INSTALL_SCRIPTS"] else { throw reject("请通过 install-workflow.sh 运行") }
            if !exists {
                guard let cookie = config.source.cookieFile else { throw reject("缺少 IPA 和 Cookie 文件：先在已登录浏览器下载到配置的 ipa 路径，或配置 cookieFile") }
                if let profile = config.source.chromeProfile {
                    _ = try run(scripts + "/export-armstore-session.sh", ["--profile", profile, "--output", cookie])
                }
                _ = try run(scripts + "/download-armstore.sh", ["--app-id", config.source.appID, "--bundle-id", config.source.bundleID,
                    "--version", config.source.version, "--country", config.source.country ?? "us", "--cookie-file", cookie, "--download", "--output", config.ipa])
                try verifyIPA(config)
            }
            for target in config.targets {
                print("安装目标：\(target.name)")
                var command = ["--api-url", target.apiURL, "--token-file", target.tokenFile]
                if config.launch ?? true { command.append("--launch") }
                command.append(config.ipa)
                _ = try run(scripts + "/install-app.sh", command)
                print("完成：\(target.name)")
            }
        } catch let error as WorkflowError {
            FileHandle.standardError.write(Data((error.message + "\n").utf8)); exit(1)
        } catch {
            FileHandle.standardError.write(Data("读取配置或执行失败；为避免泄露凭据，不输出原始错误\n".utf8)); exit(1)
        }
    }
}
