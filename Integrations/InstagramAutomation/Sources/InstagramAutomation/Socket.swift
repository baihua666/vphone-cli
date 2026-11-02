import Foundation
import Darwin
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION
struct GuestSocket {
    let path: String
    func call(_ method: String, _ params: [String: Any]) throws {
        _ = try request(method, params)
    }
    func request(_ method: String, _ params: [String: Any]) throws -> [String: Any] {
        try send(["t": "rpc", "method": method, "params": params])
    }
    func send(_ message: [String: Any]) throws -> [String: Any] {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure("无法创建 socket") }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 30, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw Failure("socket 路径过长") }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw Failure("实例未运行或 socket 不可连接") }
        var request = try JSONSerialization.data(withJSONObject: message)
        request.append(10)
        try request.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: sent), buffer.count - sent)
                guard count > 0 else { throw Failure("请求发送失败") }
                sent += count
            }
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while !data.contains(10) {
            let count = Darwin.read(fd, &buffer, buffer.count)
            guard count > 0, data.count + count <= 16 * 1024 * 1024 else { throw Failure("响应超时、关闭或过大") }
            data.append(contentsOf: buffer.prefix(count))
        }
        let line = data.prefix { $0 != 10 }
        let reply = try JSONSerialization.jsonObject(with: line) as? [String: Any]
        guard reply?["ok"] as? Bool == true else {
            let error = reply?["error"]
            let details = error as? [String: Any]
            let reason = details?["message"] as? String ?? error as? String ?? "未提供错误详情"
            let code = details?["code"] as? String ?? "unknown"
            throw Failure("guest 拒绝请求: \(message["method"] as? String ?? "transport") [\(code)] \(reason)")
        }
        return reply?["result"] as? [String: Any] ?? [:]
    }
}
#endif
