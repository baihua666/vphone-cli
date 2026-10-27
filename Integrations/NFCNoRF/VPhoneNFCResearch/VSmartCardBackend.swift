#if VPHONE_EXPERIMENTAL_NFC_NO_RF
import Darwin
import Foundation

/// Owns one Java process and one ID-less VSmartCard stream. No retries/replay on failure.
final class VPhoneNFCBackend {
    let java: String
    let classpath: String
    private var socketFD: Int32 = -1
    private var process: Process?
    var isConnected: Bool { socketFD >= 0 }
    var processIdentifier: Int32? { process?.processIdentifier }
    private(set) var port: UInt16 = 0
    static var now: Double { ProcessInfo.processInfo.systemUptime }

    init(java: String, classpath: String) { self.java = java; self.classpath = classpath }
    deinit { stop() }

    func start() throws -> [UInt8] {
        stop()
        let listener = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else { throw VPhoneNFCError.backend("socket: \(errno)") }
        defer { Darwin.close(listener) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(listener, 1) == 0 else { throw VPhoneNFCError.backend("bind/listen: \(errno)") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard withUnsafeMutablePointer(to: &address, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &length) }
        }) == 0 else { throw VPhoneNFCError.backend("getsockname: \(errno)") }
        port = UInt16(bigEndian: address.sin_port)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: java)
        child.arguments = ["-cp", classpath, "com.vphone.research.NFCNoRFCard", String(port)]
        child.standardOutput = FileHandle.standardError
        child.standardError = FileHandle.standardError
        try child.run()
        process = child
        do {
            let deadline = Self.now + 15
            try wait(listener, events: Int16(POLLIN), deadline: deadline)
            socketFD = accept(listener, nil, nil)
            guard socketFD >= 0 else { throw VPhoneNFCError.disconnected }
            guard fcntl(socketFD, F_SETFL, O_NONBLOCK) == 0 else { throw VPhoneNFCError.backend("fcntl: \(errno)") }
            var noSignal: Int32 = 1
            guard setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0
            else { throw VPhoneNFCError.backend("SO_NOSIGPIPE: \(errno)") }
            try writeFrame([2], deadline: deadline) // reset has no ACK; ATR is an ordered liveness barrier.
            try writeFrame([4], deadline: deadline)
            return try readFrame(deadline: deadline)
        } catch { stop(); throw error }
    }

    func exchange(_ apdu: [UInt8], deadline: Double) throws -> [UInt8] {
        guard isConnected else { throw VPhoneNFCError.disconnected }
        guard (4...VPhoneNFCCodec.maximumAPDU).contains(apdu.count) else { throw VPhoneNFCError.invalidFrame }
        do {
            try writeFrame(apdu, deadline: deadline)
            let reply = try readFrame(deadline: deadline)
            guard reply.count >= 2 else { throw VPhoneNFCError.invalidFrame }
            return reply
        } catch { stop(); throw error }
    }

    func stop() {
        if socketFD >= 0 { Darwin.close(socketFD); socketFD = -1 }
        guard let child = process else { return }
        process = nil
        if child.isRunning {
            kill(child.processIdentifier, SIGCONT)
            child.terminate()
            let deadline = Self.now + 1
            while child.isRunning, Self.now < deadline { usleep(10_000) }
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
        child.waitUntilExit()
    }

    private func wait(_ fd: Int32, events: Int16, deadline: Double) throws {
        while true {
            let remaining = deadline - Self.now
            guard remaining > 0 else { throw VPhoneNFCError.timeout }
            var item = pollfd(fd: fd, events: events, revents: 0)
            let result = Darwin.poll(&item, 1, Int32(min(remaining * 1000 + 1, 30_000)))
            if result < 0, errno == EINTR { continue }
            if result == 0 { continue }
            guard result > 0 else { throw VPhoneNFCError.backend("poll: \(errno)") }
            guard item.revents & Int16(POLLNVAL) == 0 else { throw VPhoneNFCError.disconnected }
            return // recv/send observes EOF and socket errors, including POLLHUP.
        }
    }

    private func writeFrame(_ bytes: [UInt8], deadline: Double) throws {
        guard !bytes.isEmpty, bytes.count <= VPhoneNFCCodec.maximumAPDU else { throw VPhoneNFCError.capacity }
        let frame = [UInt8(bytes.count >> 8), UInt8(bytes.count & 255)] + bytes
        try frame.withUnsafeBytes { buffer in
            var offset = 0
            while offset < frame.count {
                try wait(socketFD, events: Int16(POLLOUT), deadline: deadline)
                let count = send(socketFD, buffer.baseAddress!.advanced(by: offset), frame.count - offset, 0)
                if count < 0, errno == EINTR || errno == EAGAIN { continue }
                guard count > 0 else { throw VPhoneNFCError.disconnected }
                offset += count
            }
        }
    }

    private func readFrame(deadline: Double) throws -> [UInt8] {
        let header = try readExactly(2, deadline: deadline)
        let count = Int(header[0]) * 256 + Int(header[1])
        guard (1...VPhoneNFCCodec.maximumAPDU).contains(count) else { throw VPhoneNFCError.capacity }
        return try readExactly(count, deadline: deadline)
    }

    private func readExactly(_ length: Int, deadline: Double) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: length)
        try bytes.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < length {
                try wait(socketFD, events: Int16(POLLIN), deadline: deadline)
                let count = recv(socketFD, buffer.baseAddress!.advanced(by: offset), length - offset, 0)
                if count < 0, errno == EINTR || errno == EAGAIN { continue }
                guard count > 0 else { throw VPhoneNFCError.disconnected }
                offset += count
            }
        }
        return bytes
    }
}
#endif
