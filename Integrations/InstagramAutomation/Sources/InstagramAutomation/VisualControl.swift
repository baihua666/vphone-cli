import Foundation
import Vision
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION
struct VisualControl {
    let socket: GuestSocket
    func perform(text: String, tap: Bool) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 90
        repeat {
            let matches = try Screen(socket: socket).words().filter {
                $0.0.trimmingCharacters(in: .whitespacesAndNewlines) == text
            }
            if !tap, !matches.isEmpty { return }
            if matches.count == 1, let match = matches.first {
                if tap {
                    let screen = try socket.request("device.screen", [:])
                    guard let width = screen["width"] as? Double, let height = screen["height"] as? Double,
                          screen["orientation"] as? Int == 0 else { throw Failure("仅支持竖屏文字定位") }
                    try socket.call("input.tap", ["x": match.1.midX * width,
                                                  "y": (1 - match.1.midY) * height])
                    Thread.sleep(forTimeInterval: 0.6)
                }
                return
            }
            if matches.count > 1 { throw Failure("文字定位不唯一") }
            Thread.sleep(forTimeInterval: 0.5)
        } while ProcessInfo.processInfo.systemUptime < deadline
        throw Failure("画面文字等待超时")
    }
}
#endif
