import AppKit

// Lightweight owner for compiling the actual menu/server without the VM app's unrelated panels.
@MainActor
final class VPhoneMenuController: NSObject {
    var cameraServer: VPhoneCameraServer?
    var cameraStatusItem: NSMenuItem?
    var cameraSourceOffItem: NSMenuItem?
    var cameraSourceTestPatternItem: NSMenuItem?
    var cameraSourceVideoFileItem: NSMenuItem?
    var cameraStartStopItem: NSMenuItem?

    func menuSymbol(_ name: String) -> NSImage? { NSImage(systemSymbolName: name, accessibilityDescription: nil) }
    func makeItem(_ title: String, action: Selector, symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }
}

@main
struct HostCameraIntegrationTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let controller = VPhoneMenuController()
        let server = VPhoneCameraServer()
        controller.cameraServer = server
        let menu = controller.buildCameraSubmenu().submenu!
        precondition(server.sourceKind == .off)
        precondition(controller.cameraStartStopItem?.isEnabled == false)
        let hostItems = menu.items.filter { $0.title == "Source: Host Camera" }
#if VPHONE_EXPERIMENTAL_HOST_CAMERA
        precondition(hostItems.count == 1)
        let integration = hostItems[0].representedObject as! VPhoneHostCameraMenu
        let selection = NSMenuItem(title: "Unit test device", action: NSSelectorFromString("selectCamera:"), keyEquivalent: "")
        selection.target = integration
        selection.representedObject = "__unit_test_device_that_does_not_exist__"
        // Selection must not open a camera or prompt. Streaming is disabled while disconnected.
        precondition(NSApp.sendAction(selection.action!, to: selection.target, from: selection))
        precondition(server.sourceKind == .hostCamera)
        precondition(controller.cameraSourceOffItem?.state == .off)
        precondition(controller.cameraStartStopItem?.isEnabled == false)
        server.startStreaming()
        server.stopStreaming()
        controller.setCameraSourceTestPattern()
        precondition(server.sourceKind == .testPattern)
        precondition(hostItems[0].state == .off)
        controller.setCameraSourceOff()
        precondition(server.sourceKind == .off)
        precondition(controller.cameraSourceOffItem?.state == .on)
        server.setSource(.hostCamera)
        precondition(server.sourceKind == .off, "No supplied source must not claim a working host camera")
        try await ProducerLifecycleTests.run()
        try await HostCameraSimulationTests.run()
        print("PASS: enabled static menu/source hook, selection without capture, disconnected guard, fallback to baseline")
#else
        precondition(hostItems.isEmpty)
        controller.setCameraSourceTestPattern()
        precondition(server.sourceKind == .testPattern)
        controller.setCameraSourceOff()
        precondition(server.sourceKind == .off)
        print("PASS: disabled menu/source integration retains baseline without a host camera entry")
#endif
        server.disconnect()
    }
}
