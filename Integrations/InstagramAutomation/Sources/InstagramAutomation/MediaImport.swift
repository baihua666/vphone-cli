import Foundation
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION
struct MediaImport {
    let ui: Screen
    func run(image: URL, marker: String) throws {
        let info = try ui.socket.request("apps.info", ["bundle_id": "com.apple.DocumentsApp"])
        guard let groups = info["group_containers"] as? [String: String],
              let root = groups["group.com.apple.FileProvider.LocalStorage"] else {
            throw Failure("当前 Files 未提供本地存储目录")
        }
        let destination = root + "/File Provider Storage/" + marker + ".png"
        _ = try ui.socket.send(["t": "push", "local": image.path, "path": destination, "mode": "644"])
        try ui.socket.call("apps.launch", ["bundle_id": "com.apple.DocumentsApp"])
        Thread.sleep(forTimeInterval: 1)
        if try !ui.has(id: marker) {
            if try ui.has("Browse") { try ui.wait("Browse", tap: true) }
            if try ui.has("On My iPhone") { try ui.wait("On My iPhone", tap: true) }
        }
        try ui.wait(id: marker, tap: true)
        try ui.wait("Share", tap: true)
        // Share sheet AX frames can be sheet-local; OCR gives screen coordinates.
        try ui.visual("Save Image", tap: true)
        Thread.sleep(forTimeInterval: 1)
        if try ui.has("Allow Access") { try ui.wait("Allow Access", tap: true) }
        if try ui.has("Allow") { try ui.wait("Allow", tap: true) }
        try ui.wait("Image canvas")
    }
}
#endif
