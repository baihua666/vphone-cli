import Foundation

public struct VPhoneLocalApplication: Identifiable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let bundleID: String
    public let version: String
    public let build: String?
}

public struct VPhoneStoreApplication: Decodable, Identifiable, Sendable {
    public var id: Int { trackId }
    public let trackId: Int
    public let trackName: String
    public let bundleId: String
    public let version: String
}

public enum VPhoneApplicationLibrary {
    public static func inspect(_ url: URL) throws -> VPhoneLocalApplication {
        guard ["ipa", "tipa"].contains(url.pathExtension.lowercased()) else { throw fail("请选择 IPA 或 TIPA") }
        let paths = try unzip(["-Z1", url.path]).split(separator: "\n").filter {
            $0.range(of: #"^Payload/[^/]+\.app/Info\.plist$"#, options: .regularExpression) != nil
        }
        guard paths.count == 1 else { throw fail("安装包缺少唯一主应用") }
        let bytes = try command(["-p", url.path, String(paths[0])])
        guard let info = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any],
              let bundle = info["CFBundleIdentifier"] as? String, !bundle.isEmpty else { throw fail("安装包缺少 Bundle ID") }
        return VPhoneLocalApplication(url: url,
            name: info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent,
            bundleID: bundle, version: info["CFBundleShortVersionString"] as? String ?? "未知",
            build: info["CFBundleVersion"] as? String)
    }

    public static func scan(_ folders: [URL]) -> (apps: [VPhoneLocalApplication], failures: [String]) {
        var apps: [VPhoneLocalApplication] = [], failures: [String] = [], seen = Set<URL>()
        for folder in folders {
            do {
                for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) {
                    guard ["ipa", "tipa"].contains(file.pathExtension.lowercased()), seen.insert(file.resolvingSymlinksInPath()).inserted else { continue }
                    do { apps.append(try inspect(file)) }
                    catch { failures.append(file.lastPathComponent + "：" + error.localizedDescription) }
                }
            } catch { failures.append(folder.path + "：" + error.localizedDescription) }
        }
        return (apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, failures)
    }

    public static func validate(_ url: URL) throws {
        _ = try command(["-tqq", url.path])
        _ = try inspect(url)
    }

    private static func unzip(_ args: [String]) throws -> String { String(decoding: try command(args), as: UTF8.self) }
    private static func command(_ args: [String]) throws -> Data {
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); task.arguments = args
        task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw fail("IPA 归档损坏或无法读取") }
        return data
    }

    public static func search(_ query: String, country: String) async throws -> [VPhoneStoreApplication] {
        guard country.range(of: "^[a-z]{2}$", options: .regularExpression) != nil else { throw fail("地区须为两位小写代码") }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        var url = URLComponents(string: "https://itunes.apple.com/search")!
        url.queryItems = [.init(name: "term", value: term), .init(name: "country", value: country),
                          .init(name: "entity", value: "software"), .init(name: "limit", value: "40")]
        let (data, response) = try await URLSession.shared.data(from: url.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw fail("商店搜索失败") }
        struct Result: Decodable { let results: [VPhoneStoreApplication] }
        return try JSONDecoder().decode(Result.self, from: data).results
    }

    public static func download(_ app: VPhoneStoreApplication, country: String, sessionCookie: String,
                                userAgent: String, output: URL) async throws {
        let options = try Options(["--app-id", String(app.trackId), "--bundle-id", app.bundleId,
            "--version", app.version, "--country", country, "--download", "--output", output.path], hasSession: true)
        do { try await Client(options, sessionCookie: sessionCookie, userAgent: userAgent).run() }
        catch let error as ARMStoreLoginRequired { throw error }
        catch let error as DownloadError { throw error }
        catch { throw fail("下载或文件操作失败，请检查网络后重试；可打开 ARM Store 登录窗口检查账号状态。") }
    }

    public static func download(_ app: VPhoneStoreApplication, country: String, cookieFile: String, output: URL) async throws {
        let options = try Options(["--app-id", String(app.trackId), "--bundle-id", app.bundleId,
            "--version", app.version, "--country", country, "--cookie-file", cookieFile,
            "--download", "--output", output.path])
        do { try await Client(options).run() }
        catch let error as DownloadError { throw error }
        catch { throw fail("下载或文件操作失败，请检查网络与会话；未输出含凭据的 URL") }
    }
}
