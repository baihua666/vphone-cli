import Foundation

extension VPhoneCLIClient {
    public func setConfig(name: String, cpu: Int?, memoryMB: Int?, network: String?) async throws {
        var argv: [String] = []
        if let cpu { argv += ["--cpu", String(cpu)] }
        if let memoryMB { argv += ["--memory", String(memoryMB)] }
        if let network { argv += ["--network", network] }
        _ = try await runInstance(name: name, verb: "config", options: argv)
    }

    public func clone(name: String, to newName: String) async throws {
        _ = try await runInstance(name: name, verb: "clone", options: [newName])
    }

    public func rename(name: String, to newName: String) async throws {
        _ = try await runInstance(name: name, verb: "rename", options: [newName])
    }

    public func delete(name: String) async throws {
        _ = try await runInstance(name: name, verb: "delete", options: ["--force"])
    }
}
