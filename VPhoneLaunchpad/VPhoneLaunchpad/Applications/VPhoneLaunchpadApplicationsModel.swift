#if VPHONE_CUSTOM_APPLICATION_MANAGEMENT
import Foundation
import Observation
import VPhoneApplicationManagement

@MainActor @Observable
final class VPhoneLaunchpadApplicationsModel {
    var local: [VPhoneLocalApplication] = []
    var online: [VPhoneStoreApplication] = []
    var installed: [String: VPhoneInstalledApplication] = [:]
    var installedLoaded = false
    var installedLoading = false
    var installedError = ""
    private var installedRequest = UUID()
    var hideInstalled = false
    var busy = false
    var status = ""
    var query = ""
    var country = "us"
    let storeLogin = VPhoneARMStoreLogin()
    var machinePath = ""
    #if VPHONE_CUSTOM_TEMPORARY_INSTALL_MEMORY
    var memoryRetry: (app: VPhoneLocalApplication, machine: VPhoneLaunchpadMachine, reason: String)?
    var showMemoryRetry = false
    var memoryRecoveryPending = false
    #endif
    let cache = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("vphone-launchpad/Applications", isDirectory: true)

    func perform(_ operation: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await operation() }
            catch { status = VPhoneLaunchpadError.message(for: error) }
        }
    }
    func refresh() async throws {
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let folders = [cache, FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")]
        let result = await Task.detached { VPhoneApplicationLibrary.scan(folders) }.value
        local = result.apps
        status = result.failures.isEmpty ? "已读取 \(local.count) 个本地安装包" : result.failures.joined(separator: "\n")
    }
    func importPackage(_ url: URL) async throws {
        let target = cache.appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
        try await Task.detached {
            try VPhoneApplicationLibrary.validate(url)
            try FileManager.default.copyItem(at: url, to: target)
        }.value
        try await refresh()
    }
    func search() async throws {
        online = try await VPhoneApplicationLibrary.search(query, country: country)
        status = "找到 \(online.count) 个应用；下载可用性以 ARM Store 返回为准"
    }
    func download(_ app: VPhoneStoreApplication) async throws {
        status = "正在自动登录 ARM Store…"
        let (cookie, agent) = try await storeLogin.credentials(for: app)
        status = "正在请求 ARM Store、等待并下载 \(app.trackName)…"
        let destination = cache.appendingPathComponent("\(app.trackId)-\(app.version).ipa")
        do {
            try await VPhoneApplicationLibrary.download(app, country: country, sessionCookie: cookie, userAgent: agent, output: destination)
        } catch let error as ARMStoreLoginRequired {
            storeLogin.verified = false
            storeLogin.message = error.localizedDescription
            storeLogin.open()
            throw error
        }
        try await refresh()
        status = "下载完成，已加入本地应用。请核对包内版本后选择安装。"
    }
    func downloadAndInstall(_ app: VPhoneStoreApplication, machine: VPhoneLaunchpadMachine) async throws {
        #if VPHONE_CUSTOM_TEMPORARY_INSTALL_MEMORY
        guard !memoryRecoveryPending else { throw VPhoneLaunchpadError("请先恢复原内存，再下载并安装。") }
        #endif
        try await download(app)
        let url = cache.appendingPathComponent("\(app.trackId)-\(app.version).ipa")
        let package = try await Task.detached { try VPhoneApplicationLibrary.inspect(url) }.value
        try await install(package, machine: machine)
    }
    func rpc(_ machine: VPhoneLaunchpadMachine, _ method: String) async throws -> [String: Any] {
        let reply = try await VPhoneLaunchpadGuestSocket.send(
            ["t": "rpc", "method": method, "params": [:]], socketPath: machine.path.url.appendingPathComponent("vphone.sock").path)
        guard let envelope = reply as? [String: Any], let result = envelope["result"] as? [String: Any] else {
            throw VPhoneLaunchpadError("无法读取客体响应")
        }
        return result
    }
    func refreshInstalled(_ machine: VPhoneLaunchpadMachine) async throws {
        let request = UUID()
        installedRequest = request
        installed = [:]
        installedLoaded = false
        installedLoading = true
        installedError = ""
        defer { if installedRequest == request { installedLoading = false } }
        do {
            let result = try await rpc(machine, "apps.list")
            let apps = try VPhoneInstalledApplication.parse(result)
            guard installedRequest == request, machinePath == machine.path.url.path else { return }
            installed = apps
            installedLoaded = true
        } catch {
            guard installedRequest == request, machinePath == machine.path.url.path else { return }
            installedError = "无法读取目标机已安装版本：\(VPhoneLaunchpadError.message(for: error))"
            throw error
        }
    }
    func clearInstalled() {
        installedRequest = UUID()
        installed = [:]
        installedLoaded = false
        installedLoading = false
        installedError = ""
        hideInstalled = false
    }
    func install(_ app: VPhoneLocalApplication, machine: VPhoneLaunchpadMachine) async throws {
        #if VPHONE_CUSTOM_TEMPORARY_INSTALL_MEMORY
        guard !memoryRecoveryPending else { throw VPhoneLaunchpadError("请先恢复未完成流程的原内存，再安装应用。") }
        #endif
        do { try await installOnce(app, machine: machine) }
        catch {
            #if VPHONE_CUSTOM_TEMPORARY_INSTALL_MEMORY
            if error is VPhoneApplicationInstallUnconfirmed, machine.memoryMB < 8192, !memoryRecoveryPending {
                memoryRetry = (app, machine, VPhoneLaunchpadError.message(for: error))
                showMemoryRetry = true
            }
            #endif
            throw error
        }
    }

    func installOnce(_ app: VPhoneLocalApplication, machine: VPhoneLaunchpadMachine) async throws {
        let socket = machine.path.url.appendingPathComponent("vphone.sock").path
        status = "正在安装 \(app.name) 到 \(machine.name)…"
        let connection = try VPhoneLaunchpadApplicationConnection.read(VPhoneLaunchpadMachineLibrary.consoleLog(machine.path))
        _ = try await VPhoneApplicationInstallation.install(url: app.url, bundleID: app.bundleID, upload: { url, path in
            try await connection.upload(url, to: path)
        }) { request, timeout in
            let reply: Any
            do {
                reply = try await VPhoneLaunchpadGuestSocket.send(request, socketPath: socket, timeout: timeout)
            } catch {
                // Preserve the host's concrete error before crossing the package boundary.
                throw NSError(domain: "VPhoneApplicationTransport", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: VPhoneLaunchpadError.message(for: error)])
            }
            guard let result = reply as? [String: Any] else { throw VPhoneLaunchpadError("无法读取宿主响应") }
            return result
        }
        do { try await refreshInstalled(machine) }
        catch {
            status = "\(app.name) 已安装并确认，但版本详情读取失败，请重新读取已安装列表。"
            return
        }
        status = "\(app.name) 已安装到 \(machine.name)，并已读回确认"
    }
}
#endif
