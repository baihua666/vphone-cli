#if VPHONE_EXPERIMENTAL_HOST_CAMERA
import AppKit

@MainActor
final class VPhoneHostCameraMenu: NSObject, NSMenuDelegate {
    private weak var controller: VPhoneMenuController?
    private weak var root: NSMenuItem?
    private var selectedID: String?
    private var selection = UUID()

    static func install(in menu: NSMenu, controller: VPhoneMenuController) {
        let integration = VPhoneHostCameraMenu()
        integration.controller = controller
        let root = NSMenuItem(title: "Source: Host Camera", action: nil, keyEquivalent: "")
        integration.root = root
        let submenu = NSMenu(title: "Host Camera")
        submenu.autoenablesItems = false
        submenu.delegate = integration
        root.submenu = submenu
        // NSMenuItem.target/delegate are weak; retain only the integration, never the VM controller.
        root.representedObject = integration
        menu.addItem(root)
    }

    static func refresh(controller: VPhoneMenuController) {
        for item in controller.cameraSourceOffItem?.menu?.items ?? [] {
            (item.representedObject as? VPhoneHostCameraMenu)?.refresh()
        }
    }

    private func refresh() {
        guard let controller, let server = controller.cameraServer else { return }
        root?.state = server.sourceKind == .hostCamera ? .on : .off
        if server.sourceKind != .hostCamera {
            selection = UUID()
            controller.updateCameraConnectionState(connected: server.isConnected)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
        menu.removeAllItems()
        let devices = VPhoneHostCameraCapture.devices()
        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(selectCamera(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.id
            item.state = root?.state == .on && selectedID == device.id ? .on : .off
            menu.addItem(item)
        }
        if devices.isEmpty {
            let item = NSMenuItem(title: "No host cameras found", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
    }

    @objc private func selectCamera(_ item: NSMenuItem) {
        guard let controller, let server = controller.cameraServer,
              let deviceID = item.representedObject as? String else { return }
        // Invalidate old callbacks before replacing the source (which stops its capture).
        selection = UUID()
        let token = selection
        selectedID = deviceID
        let producer = VPhoneHostCameraProducer(deviceID: deviceID) { [weak self, weak server] state in
            guard let self, selection == token, let server, server.sourceKind == .hostCamera else { return }
            update(state, server: server)
        }
        server.setSource(.hostCamera, externalProducer: producer)
        controller.cameraSourceOffItem?.state = .off
        controller.cameraSourceTestPatternItem?.state = .off
        controller.cameraSourceVideoFileItem?.state = .off
        root?.state = .on
        controller.cameraStartStopItem?.isEnabled = server.isConnected
    }

    private func update(_ state: VPhoneHostCameraProducer.State, server: VPhoneCameraServer) {
        guard let controller else { return }
        switch state {
        case .starting:
            controller.cameraStatusItem?.title = "Host camera: starting…"
        case .running:
            controller.cameraStatusItem?.title = "Host camera: capturing"
        case .stopped:
            controller.updateCameraConnectionState(connected: server.isConnected)
        case let .failed(message):
            // Stop also invalidates a pending permission request; it must never turn the camera on later.
            server.stopStreaming()
            controller.cameraStartStopItem?.title = VPhoneLocalization.text("Start Streaming")
            controller.cameraStartStopItem?.image = NSImage(systemSymbolName: "play", accessibilityDescription: nil)
            controller.cameraStatusItem?.title = "Host camera: unavailable"
            VPhoneAlert.present(title: "Host Camera", message: message, style: .warning)
        }
    }
}
#endif
