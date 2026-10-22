import Foundation

extension VMCommandContext {
    static func launchpadExecutable(directory: URL, store: URL) throws -> URL {
        struct Binding: Decodable { let bundle: String }
        do {
            let file = directory.appendingPathComponent("launchpad.json")
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw invalidBinding() }
            let binding = try JSONDecoder().decode(Binding.self, from: Data(contentsOf: file))
            guard binding.bundle.range(of: #"^[0-9A-Za-z][0-9A-Za-z._-]{0,63}$"#, options: .regularExpression) != nil,
                  !binding.bundle.contains("..") else { throw invalidBinding() }
            return store.appendingPathComponent(binding.bundle)
                .appendingPathComponent("VPhone.bundle/Contents/MacOS/vphone-cli")
        } catch { throw invalidBinding() }
    }

    private static func invalidBinding() -> ProxyRouteError {
        ProxyRouteError("Launchpad 实例绑定缺失或无效，请先绑定已安装的核心 Bundle")
    }

    /// Re-read bindings before every proxy operation. A default or stale Workstation
    /// sidecar must never stand in for Launchpad's authoritative per-machine binding.
    func validateProxyIsolation() throws {
        let fm = FileManager.default
        if let launchpadStore {
            guard try Self.launchpadExecutable(directory: directory, store: launchpadStore) == executable else {
                throw ProxyRouteError("核心 Bundle 绑定已变化，请刷新后重试")
            }
        }
        let roots = Set(isolationRoots + [directory.deletingLastPathComponent().path])
        for root in roots {
            let siblings = try fm.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil)
            for sibling in siblings where sibling.resolvingSymlinksInPath().path != directory.resolvingSymlinksInPath().path {
                guard fm.fileExists(atPath: sibling.appendingPathComponent("config.plist").path)
                    || fm.fileExists(atPath: sibling.appendingPathComponent(".vphone-ws.json").path) else { continue }
                let bound: URL
                if let launchpadStore {
                    bound = try Self.launchpadExecutable(directory: sibling, store: launchpadStore)
                } else {
                    struct Binding: Decodable { let executablePath: String }
                    guard let data = try? Data(contentsOf: sibling.appendingPathComponent(".vphone-ws.json")),
                          let binding = try? JSONDecoder().decode(Binding.self, from: data),
                          binding.executablePath.hasPrefix("/") else {
                        throw ProxyRouteError("库中存在未绑定运行程序的实例，无法验证出口隔离")
                    }
                    bound = URL(fileURLWithPath: binding.executablePath)
                }
                if bound.resolvingSymlinksInPath() == executable.resolvingSymlinksInPath() {
                    throw ProxyRouteError("多个实例共用此运行程序，无法按进程路径隔离出口")
                }
            }
        }
    }
}
