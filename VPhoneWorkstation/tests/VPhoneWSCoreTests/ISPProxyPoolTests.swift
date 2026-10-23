import Testing
@testable import VPhoneWSCore

@Test func ispPoolUsesActualGatewayAndStaticPorts() throws {
    let yaml = """
    proxies:
      - {name: renamed, server: isp.decodo.com, port: 10001, type: http}
      - {name: rotating, server: isp.decodo.com, port: 10000, type: http}
      - {name: fake-ISP-name, server: gate.decodo.com, port: 10002, type: http}
      - {name: invalid, server: isp.decodo.com, port: 63001, type: http}
    """
    #expect(try ISPProxyPool.names(runtime: yaml) == ["renamed"])
}
