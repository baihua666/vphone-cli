import Foundation
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION
struct PhotoSelection {
    let ui: Screen
    func grant(marker: String) throws {
        try ui.wait(id: "Update")
        try ui.waitMarker(marker)
        let matches = try ui.markerMatches(marker)
        guard matches.count == 1, let box = matches.first?.1 else { throw Failure("相册中测试图片编号不唯一") }
        let screen = try ui.socket.request("device.screen", [:])
        guard let width = screen["width"] as? Double, let height = screen["height"] as? Double,
              screen["orientation"] as? Int == 0 else { throw Failure("照片选择仅支持竖屏") }
        let point = CGPoint(x: box.midX * width, y: (1 - box.midY) * height)
        let cells = try ui.tree().filter { element in
            guard element["identifier"] as? String == "PXGGridLayout-Info",
                  let frame = element["frame"] as? [String: Double], let x = frame["x"], let y = frame["y"],
                  let w = frame["width"], let h = frame["height"] else { return false }
            return CGRect(x: x, y: y, width: w, height: h).contains(point)
        }
        guard cells.count == 1, let cell = cells.first else { throw Failure("无法将测试编号对应到照片格子") }
        let selected = (cell["traits"] as? UInt64 ?? 0) & 8 != 0
        if !selected {
            try ui.socket.call("input.tap", ["x": point.x, "y": point.y])
            Thread.sleep(forTimeInterval: 0.6)
        }
        try ui.wait(id: "Update", tap: true)
    }
}
#endif
