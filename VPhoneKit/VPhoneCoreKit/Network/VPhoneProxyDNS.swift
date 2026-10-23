import Foundation
import Security

/// DNS-over-HTTPS inside the already authenticated per-VM CONNECT tunnel.
/// SecureTransport wraps the socketpair without opening another host connection.
/// Decodo rejects CONNECT :53. DNS must not fall back to the host resolver.
enum VPhoneProxyDNS {
    static func exchange(_ query: [UInt8], descriptor: Int32, resolver: String) -> [UInt8]? {
        defer { Darwin.close(descriptor) }
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL, 0) & ~O_NONBLOCK)
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        _ = setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        guard let tls = SSLCreateContext(nil, .clientSide, .streamType) else { return nil }
        SSLSetIOFuncs(tls, { connection, buffer, length in
            let fd = Int32(Int(bitPattern: connection) - 1)
            let requested = length.pointee
            let n = Darwin.recv(fd, buffer, requested, 0)
            length.pointee = max(0, n)
            if n == 0 { return errSSLClosedGraceful }
            if n < 0 { return errSSLClosedAbort }
            return n == requested ? noErr : errSSLWouldBlock
        }, { connection, buffer, length in
            let fd = Int32(Int(bitPattern: connection) - 1)
            let requested = length.pointee
            let n = Darwin.send(fd, buffer, requested, 0)
            length.pointee = max(0, n)
            if n <= 0 { return errSSLClosedAbort }
            return n == requested ? noErr : errSSLWouldBlock
        })
        SSLSetConnection(tls, UnsafeRawPointer(bitPattern: Int(descriptor) + 1))
        resolver.withCString { _ = SSLSetPeerDomainName(tls, $0, strlen($0)) }
        // Default trust verification stays enabled, including the resolver's certificate identity.
        let deadline = Date().addingTimeInterval(15)
        var status = SSLHandshake(tls)
        while status == errSSLWouldBlock && Date() < deadline { status = SSLHandshake(tls) }
        guard status == noErr else { return nil }
        let encoded = Data(query).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        var request = Data("GET /dns-query?dns=\(encoded) HTTP/1.1\r\nHost: \(resolver)\r\nAccept: application/dns-message\r\nConnection: close\r\n\r\n".utf8)
        while !request.isEmpty && Date() < deadline {
            var sent = 0
            status = request.withUnsafeBytes { SSLWrite(tls, $0.baseAddress!, $0.count, &sent) }
            guard status == noErr || status == errSSLWouldBlock else { return nil }
            request.removeFirst(sent)
        }
        guard request.isEmpty else { return nil }
        var response = Data(); var buffer = [UInt8](repeating: 0, count: 16384)
        while Date() < deadline && response.count <= 131072 {
            var count = 0
            status = SSLRead(tls, &buffer, buffer.count, &count)
            response.append(contentsOf: buffer.prefix(count))
            if let answer = parse(response) { return answer }
            guard status == noErr || status == errSSLWouldBlock else { return nil }
        }
        return nil
    }

    static func parse(_ data: Data) -> [UInt8]? {
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let lines = String(decoding: data[..<boundary.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        guard lines.first?.split(separator: " ").dropFirst().first == "200",
              let field = lines.first(where: { $0.lowercased().hasPrefix("content-length:") }),
              let length = Int(field.dropFirst(15).trimmingCharacters(in: .whitespaces)),
              (12...65535).contains(length), data.count - boundary.upperBound >= length else { return nil }
        return Array(data[boundary.upperBound..<boundary.upperBound + length])
    }
}
