import Foundation
import PhotoPicker
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION && VPHONE_CUSTOM_THREADS_AUTOMATION
/// UI validation deliberately has no journal, import, caption, login or publish operation.
struct ThreadsPhotoValidation {
    let ui: Screen
    let image: URL

    static func execute(hasAttachment: () throws -> Bool, openPicker: () throws -> Void,
                        select: () throws -> Void, confirm: () throws -> Void, verify: () throws -> Void) throws {
        if try !hasAttachment() {
            try openPicker()
            try select()
            try confirm()
        }
        try verify()
    }

    func run() throws {
        guard PhotoPicker.isEnabled else { throw Failure("通用照片选择未编译启用") }
        let picker = PhotoPicker(rpc: ui.socket.request)
        try Self.execute(hasAttachment: {
            let count = ThreadsPost.attachmentCount(try ui.tree())
            guard count <= 1 else { throw Failure("当前草稿不止一张附件，停止验证") }
            return count == 1
        }, openPicker: {
            if try ui.has(id: "composer-text-view") {
                try ui.wait("Add photos and videos from your camera roll", tap: true)
            }
            try ui.wait("Done")
        }, select: {
            try picker.select(image: image)
            print("photo-validation: selected one matching photo")
        }, confirm: {
            try ui.wait("Done", tap: true)
            try ui.wait(id: "composer-text-view")
            let deadline = Date().addingTimeInterval(15)
            while true {
                let count = ThreadsPost.attachmentCount(try ui.tree())
                if count == 1 { break }
                guard count == 0, Date() < deadline else { throw Failure("未确认单张附件，停止验证") }
                Thread.sleep(forTimeInterval: 0.2)
            }
        }, verify: {
            try picker.verify(image: image, identifier: "image-view")
            print("photo-validation: attachment verified; not published")
        })
    }
}
#endif
