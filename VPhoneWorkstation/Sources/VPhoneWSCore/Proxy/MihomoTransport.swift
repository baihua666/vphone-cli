import Foundation

protocol MihomoTransport: Sendable {
    func request(socket: String, secret: String, method: String, path: String, body: Data?) async throws -> Data
}

/// System curl supports Unix-domain HTTP; credentials travel over stdin, never argv or disk.
struct SystemMihomoTransport: MihomoTransport {
    func request(socket: String, secret: String, method: String, path: String, body: Data?) async throws -> Data {
        try await Task.detached {
            let process = Process()
            let input = Pipe(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = ["--disable", "--silent", "--fail", "--max-time", "20", "--noproxy", "*",
                                 "--unix-socket", socket, "--request", method, "--config", "-", "http://localhost" + path]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            func escaped(_ value: String) -> String {
                value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r")
            }
            var config = "header = \"Authorization: Bearer \(escaped(secret))\"\n"
            if let body {
                config += "header = \"Content-Type: application/json\"\ndata = \"\(escaped(String(decoding: body, as: UTF8.self)))\"\n"
            }
            try process.run()
            try input.fileHandleForWriting.write(contentsOf: Data(config.utf8))
            try input.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw ProxyRouteError("Mihomo 请求失败（curl \(process.terminationStatus)）；请确认 Clash Verge 正在运行")
            }
            return data
        }.value
    }
}
