import Testing
@testable import VPhoneWSCore

#if VPHONE_CUSTOM_NATIVE_INTERFACE_SELECTION
@Test func physicalInterfaceChoiceIsMachineLocalAndExcludesTunnelDefault() {
    typealias Interface = NativePhysicalNetwork.Interface
    let laptop = [Interface(device: "en0", kind: "wifi", hasIPv4: true)]
    let desktop = [Interface(device: "en0", kind: "ethernet", hasIPv4: false), Interface(device: "en1", kind: "wifi", hasIPv4: true)]
    let usb = [Interface(device: "en7", kind: "ethernet", hasIPv4: true), Interface(device: "en0", kind: "wifi", hasIPv4: false)]
    #expect(NativePhysicalNetwork.choose(laptop, primary: "en0")?.device == "en0")
    #expect(NativePhysicalNetwork.choose(desktop, primary: "utun4")?.device == "en1")
    #expect(NativePhysicalNetwork.choose(usb, primary: "en7")?.kind == "ethernet")
    #expect(NativePhysicalNetwork.choose(usb, primary: "en7", kind: "wifi")?.device == "en0")
    #expect(NativePhysicalNetwork.choose([], primary: "utun0") == nil)
    let disconnected = [Interface(device: "en0", kind: "ethernet", hasIPv4: false), Interface(device: "en7", kind: "ethernet", hasIPv4: false)]
    #expect(NativePhysicalNetwork.choose(disconnected, primary: nil) == nil)
}
#endif
