import Foundation

/// A single resolution of an instance, shared by launch, queries and mutations.
public struct VMCommandContext: Sendable {
    public let executable: URL
    public let directory: URL
    public let libraryRoot: String?
    public let variant: String?
    public let isAlias: Bool
    public var name: String { directory.lastPathComponent }

    public init(name: String, executable: URL, libraryRoot: String?) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
            throw VPhoneCLIError.decodeFailed("Invalid instance name")
        }
        let root = libraryRoot ?? AppEnvironment.defaultLibraryRoot()
        let requested = URL(fileURLWithPath: root).resolvingSymlinksInPath().appendingPathComponent(name)
        directory = requested.resolvingSymlinksInPath()
        isAlias = requested.standardizedFileURL.path != directory.path
        self.libraryRoot = libraryRoot == nil && !isAlias ? nil : directory.deletingLastPathComponent().path
        struct Binding: Decodable { let variant: String?; let executablePath: String? }
        let sidecar = directory.appendingPathComponent(".vphone-ws.json")
        if FileManager.default.fileExists(atPath: sidecar.path) {
            // Corrupt bindings must never silently select the default runtime.
            let binding = try JSONDecoder().decode(Binding.self, from: Data(contentsOf: sidecar))
            if let path = binding.executablePath {
                guard path.hasPrefix("/"), !path.isEmpty else {
                    throw VPhoneCLIError.decodeFailed("Instance CLI path must be absolute")
                }
                self.executable = URL(fileURLWithPath: path)
            } else { self.executable = executable }
            variant = binding.variant
        } else {
            self.executable = executable
            variant = nil
        }
    }

    public func arguments(_ verb: String, options: [String] = []) -> [String] {
        var args = ["vm", verb, name] + options
        if let libraryRoot { args += ["--library-root", libraryRoot] }
        return args
    }
}
