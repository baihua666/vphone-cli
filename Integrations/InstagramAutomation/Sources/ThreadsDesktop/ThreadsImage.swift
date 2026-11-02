#if VPHONE_CUSTOM_THREADS_DESKTOP
import AppKit

public enum ThreadsImage {
    /// Keep the selected file byte-for-byte: no watermark, resizing or recompression.
    public static func prepare(source: URL, marker: String, destination: URL) throws {
        guard let image = NSImage(contentsOf: source), image.size.width > 0, image.size.height > 0 else {
            throw ThreadsDesktopError("无法读取所选图片")
        }
        try Data(contentsOf: source).write(to: destination, options: .atomic)
    }
}
#endif
