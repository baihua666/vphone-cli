import Foundation
import PhotoPicker
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION && VPHONE_CUSTOM_THREADS_AUTOMATION
/// Business adapter: generic selection owns layout, coordinates and duplicate matching.
struct ThreadsOriginalPhoto {
    let ui: Screen
    let source: URL
    func select(permission: Bool) throws {
        try PhotoPicker(rpc: ui.socket.request).select(image: source)
    }
    func checkAttachment() throws {
        try PhotoPicker(rpc: ui.socket.request).verify(image: source, identifier: "image-view")
    }
}
#endif
