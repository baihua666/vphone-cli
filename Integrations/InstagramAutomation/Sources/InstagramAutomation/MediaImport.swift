import Foundation
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION
struct MediaImport {
    let ui: Screen
    private func progress(_ text: String) { print("import: \(text)"); fflush(stdout) }
    func run(image: URL, marker: String) throws {
        progress("检查 Files 存储")
        let info = try ui.socket.request("apps.info", ["bundle_id": "com.apple.DocumentsApp"])
        guard let groups = info["group_containers"] as? [String: String],
              let root = groups["group.com.apple.FileProvider.LocalStorage"] else {
            throw Failure("当前 Files 未提供本地存储目录")
        }
        let destination = root + "/File Provider Storage/" + marker + "." + image.pathExtension
        progress("传入原图")
        _ = try ui.socket.send(["t": "push", "local": image.path, "path": destination, "mode": "644"])
        progress("打开 Files")
        try ui.socket.call("apps.launch", ["bundle_id": "com.apple.DocumentsApp"])
        Thread.sleep(forTimeInterval: 1)
        progress("查找导入文件")
        if try !ui.has(id: marker) {
            if try ui.has("Browse") { try ui.wait("Browse", tap: true) }
            if try ui.has("On My iPhone") { try ui.wait("On My iPhone", tap: true) }
        }
        try ui.wait(id: marker, tap: true)
        progress("打开分享面板")
        try ui.wait("Share", tap: true)
        // Share sheet AX frames can be sheet-local; OCR gives screen coordinates.
        progress("保存图片到相册")
        try ui.visual("Save Image", tap: true)
        Thread.sleep(forTimeInterval: 1)
        progress("检查相册授权与保存结果")
        if try ui.has("Allow Access") { try ui.wait("Allow Access", tap: true) }
        if try ui.has("Allow") { try ui.wait("Allow", tap: true) }
        try ui.wait("Image canvas")
    }
}
#endif
