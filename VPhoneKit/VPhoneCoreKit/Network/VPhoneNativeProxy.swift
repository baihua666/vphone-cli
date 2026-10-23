import Foundation
import Network
import Security

/// Generic per-VM HTTPS CONNECT transport. Provider-specific city/session rules stay in the UI service.
public struct VPhoneNativeProxy: Codable, Sendable, Equatable {
    public var host: String
    public var address: String
    public var port: UInt16
    public var username: String
    public var password: String
    public var interface: String
    public var dnsAddress: String

    public func validate() throws {
        var ip = in_addr()
        guard inet_pton(AF_INET, address, &ip) == 1, !address.hasPrefix("198.18."), !address.hasPrefix("198.19."),
              inet_pton(AF_INET, dnsAddress, &ip) == 1, port > 0,
              !host.isEmpty, host.utf8.allSatisfy({ $0 > 32 && $0 < 127 }),
              ["wifi", "ethernet"].contains(interface),
              !username.contains(":"), !username.contains("\n"), !password.contains("\n") else {
            throw NSError(domain: "VPhoneNativeProxy", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid native proxy endpoint or physical interface"])
        }
    }

    public static func load(_ url: URL) throws -> Self {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.posixPermissions] as? Int ?? 0) & 0o077 == 0,
              (attrs[.size] as? Int ?? Int.max) < 65536 else {
            throw NSError(domain: "VPhoneNativeProxy", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Proxy configuration must be a private regular file (0600)"])
        }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try value.validate()
        return value
    }
}

/// Adapts an authenticated TLS stream to the existing fd-based TCP forwarder.
/// All callbacks and lifecycle transitions run on the forwarder's serial queue.
final class VPhoneHTTPSProxyBridge: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var completion: (@Sendable (Int32?) -> Void)?
    private var header = Data()
    private var peer: Int32 = -1
    private var reader: DispatchSourceRead?
    private var writer: DispatchSourceWrite?
    private var pending = Data()
    private var stopped = false
    private var localEnded = false
    private var remoteEnded = false
    private var request: Data

    init(proxy: VPhoneNativeProxy, destination: String, port: UInt16, queue: DispatchQueue,
         completion: @escaping @Sendable (Int32?) -> Void) {
        self.queue = queue; self.completion = completion
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, proxy.host)
        sec_protocol_options_set_tls_resumption_enabled(tls.securityProtocolOptions, false)
        sec_protocol_options_set_tls_tickets_enabled(tls.securityProtocolOptions, false)
        // Decodo's TLS 1.3 gateway failed subsequent connections across ISP ports in live tests.
        // This affects the outer proxy tunnel only; guest HTTPS retains its own TLS negotiation.
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.requiredInterfaceType = proxy.interface == "wifi" ? .wifi : .wiredEthernet
        // macOS system HTTP proxies otherwise redirect this TLS connection back to Clash.
        parameters.preferNoProxies = true
        parameters.setPrivacyContext(NWParameters.PrivacyContext(description: "vphone-native-\(UUID().uuidString)"))
        connection = NWConnection(host: NWEndpoint.Host(proxy.address), port: NWEndpoint.Port(rawValue: proxy.port)!, using: parameters)
        let auth = Data("\(proxy.username):\(proxy.password)".utf8).base64EncodedString()
        request = Data("CONNECT \(destination):\(port) HTTP/1.1\r\nHost: \(destination):\(port)\r\nProxy-Authorization: Basic \(auth)\r\n\r\n".utf8)
    }

    func start() {
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                connection.send(content: request, completion: .contentProcessed { [self] error in
                    request.removeAll()
                    if error != nil { stop() } else { readHeader() }
                })
            case .failed, .cancelled: stop()
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 15) { [weak self] in
            if self?.completion != nil { self?.stop() }
        }
    }

    private func readHeader() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [self] data, _, ended, error in
            guard !stopped, error == nil, !ended, let data else { stop(); return }
            header.append(data)
            guard header.count < 32768 else { stop(); return }
            if let boundary = header.range(of: Data("\r\n\r\n".utf8)) {
                let line = String(decoding: header.prefix(upTo: boundary.lowerBound), as: UTF8.self)
                    .components(separatedBy: "\r\n").first ?? ""
                guard line.split(separator: " ").dropFirst().first == "200" else { stop(); return }
                var pair: [Int32] = [-1, -1]
                guard socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0 else { stop(); return }
                peer = pair[1]
                for fd in pair {
                    var one: Int32 = 1
                    _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
                    _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)
                }
                let callback = completion; completion = nil
                let source = DispatchSource.makeReadSource(fileDescriptor: peer, queue: queue)
                source.setEventHandler { [self] in readLocal() }
                reader = source; source.resume()
                pending = Data(header.suffix(from: boundary.upperBound)); header.removeAll()
                callback?(pair[0])
                flushRemote()
            } else { readHeader() }
        }
    }

    private func readLocal() {
        guard !stopped else { return }
        var buffer = [UInt8](repeating: 0, count: 16384)
        let count = recv(peer, &buffer, buffer.count, 0)
        if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { return }
        if count == 0 {
            localEnded = true; reader?.cancel(); reader = nil
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [self] error in
                if error != nil || remoteEnded { stop() }
            })
            queue.asyncAfter(deadline: .now() + 30) { [weak self] in self?.stop() }
            return
        }
        guard count > 0 else { stop(); return }
        // One bounded write at a time: do not accumulate unbounded guest uploads.
        reader?.cancel(); reader = nil
        connection.send(content: Data(buffer.prefix(count)), completion: .contentProcessed { [self] error in
            guard !stopped, error == nil else { stop(); return }
            let source = DispatchSource.makeReadSource(fileDescriptor: peer, queue: queue)
            source.setEventHandler { [self] in readLocal() }
            reader = source; source.resume()
        })
    }

    private func readRemote() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [self] data, _, ended, error in
            guard !stopped, error == nil else { stop(); return }
            if let data { pending.append(data) }
            remoteEnded = ended
            flushRemote()
        }
    }

    private func flushRemote() {
        guard !stopped else { return }
        while !pending.isEmpty {
            let count = pending.withUnsafeBytes { send(peer, $0.baseAddress, $0.count, 0) }
            if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                if writer == nil {
                    let source = DispatchSource.makeWriteSource(fileDescriptor: peer, queue: queue)
                    source.setEventHandler { [self] in flushRemote() }
                    writer = source; source.resume()
                }
                return
            }
            guard count > 0 else { stop(); return }
            pending.removeFirst(count)
        }
        writer?.cancel(); writer = nil
        if remoteEnded {
            _ = shutdown(peer, SHUT_WR)
            if localEnded { stop() }
            return
        }
        readRemote()
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        reader?.cancel(); reader = nil; writer?.cancel(); writer = nil
        if peer >= 0 { Darwin.close(peer); peer = -1 }
        connection.stateUpdateHandler = nil; connection.cancel()
        let callback = completion; completion = nil; callback?(nil)
    }
}
