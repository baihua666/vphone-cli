import Foundation
import Testing
@testable import VPhoneCoreKit

struct VPhoneNativeProxyTests {
    func config() -> VPhoneNativeProxy {
        VPhoneNativeProxy(host: "isp.decodo.com", address: "203.0.113.1", port: 10001,
            username: "user-test", password: "test", interface: "wifi", dnsAddress: "1.1.1.1")
    }

    @Test func rejectsFakeGatewayAndPublicCredentialFiles() throws {
        var value = config(); value.address = "198.18.1.2"
        #expect(throws: (any Error).self) { try value.validate() }
        value = config(); value.interface = "utun4"
        #expect(throws: (any Error).self) { try value.validate() }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try JSONEncoder().encode(config()).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        #expect(throws: (any Error).self) { try VPhoneNativeProxy.load(file) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        #expect(try VPhoneNativeProxy.load(file) == config())
    }

    @Test func dnsDoesNotAcceptTruncatedOrErrorResponses() {
        let body = Data(repeating: 0, count: 12)
        let header = Data("HTTP/1.1 200 OK\r\nContent-Length: 12\r\n\r\n".utf8)
        #expect(VPhoneProxyDNS.parse(header + body) == Array(body))
        #expect(VPhoneProxyDNS.parse(header + body.prefix(5)) == nil)
        #expect(VPhoneProxyDNS.parse(Data("HTTP/1.1 403 Forbidden\r\nContent-Length: 12\r\n\r\n".utf8) + body) == nil)
    }

    @Test func modeIsPerNetworkAndSwitchBackIsExplicit() throws {
        let a = try VPhoneUserspaceNetwork(), b = try VPhoneUserspaceNetwork()
        a.start(); b.start(); defer { a.stop(); b.stop() }
        try a.setNativeProxy(config())
        #expect(a.usesNativeProxy); #expect(!b.usesNativeProxy)
        #expect(a.nativeProxyEndpoint == "isp.decodo.com:10001")
        try b.setNativeProxy(config())
        try a.setNativeProxy(nil)
        #expect(!a.usesNativeProxy); #expect(b.usesNativeProxy)
        #expect(a.nativeProxyEndpoint == nil)
    }
@Test func udpCannotEscapeNativeModeButReturnsAfterExplicitFallback() throws {
    let listener = socket(AF_INET, SOCK_DGRAM, 0)
    defer { Darwin.close(listener) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = UInt32(0x7f000001).bigEndian
    let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
    } }
    try #require(bound == 0)
    var size = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &size) } }
    let port = UInt16(bigEndian: address.sin_port)
    var timeout = timeval(tv_sec: 0, tv_usec: 300000)
    _ = setsockopt(listener, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var pair: [Int32] = [-1, -1]
    try #require(socketpair(AF_UNIX, SOCK_DGRAM, 0, &pair) == 0)
    let c = VPhoneUserspaceNetworkConfiguration.default
    let network = try VPhoneUserspaceNetwork(configuration: c, guestDescriptor: pair[0], hostDescriptor: pair[1])
    network.start(); defer { network.stop() }
    let udp = VPhoneUDPDatagram(sourcePort: 51000, destinationPort: port, payload: [1, 2, 3])
    let frame = VPhoneEthernetFrame(destination: .gateway, source: .init([2, 1, 2, 3, 4, 5]), etherType: .ipv4,
        payload: VPhoneIPv4Packet(source: c.guestAddress, destination: c.hostAddress, proto: .udp,
            payload: udp.bytes(source: c.guestAddress, destination: c.hostAddress)).bytes).bytes
    try network.setNativeProxy(config())
    _ = frame.withUnsafeBytes { send(pair[0], $0.baseAddress, $0.count, 0) }
    var buffer = [UInt8](repeating: 0, count: 32)
    #expect(recv(listener, &buffer, buffer.count, 0) == -1)
    try network.setNativeProxy(nil)
    _ = frame.withUnsafeBytes { send(pair[0], $0.baseAddress, $0.count, 0) }
    #expect(recv(listener, &buffer, buffer.count, 0) == 3)
}

}
