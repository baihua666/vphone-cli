import Foundation
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION
struct PostTest {
    let ui: Screen
    let journal: RunJournal
    var caption: String { journal.state.marker + "\nAutomated end-to-end test. Generated test image; no personal content." }
    func prepare() throws {
        let inPicker = (try? ui.has(id: "Update")) == true
        let inMenu = (try? ui.has("Select more photos")) == true
        let words = try ui.words().map(\.0)
        let inComposer = words.contains("New post")
        let inEditor = words.contains("Filter") && words.contains("Edit")
        let inCaption = words.contains("Share") || words.contains("Add a caption...")
        let inCaptionEditor = words.contains("Caption")
        if !inPicker && !inMenu && !inComposer && !inEditor && !inCaption && !inCaptionEditor {
            try Login(ui: ui, journal: journal).profile()
            try ui.wait(id: "profile-add-button", tap: true)
            try ui.wait("Post", tap: true)
            try ui.visual("New post")
        }
        // Instagram can expose only a limited photo library. Grant only the new fixture.
        if !inEditor && !inCaption && !inCaptionEditor {
            if !inPicker && !inMenu, try ui.words().contains(where: { $0.0 == "Manage" }) {
                try ui.visual("Manage", tap: true)
                try ui.wait("Select more photos", tap: true)
            } else if inMenu { try ui.wait("Select more photos", tap: true) }
            if (try? ui.has(id: "Update")) == true {
                try PhotoSelection(ui: ui).grant(marker: journal.state.marker)
            }
            try ui.visual("New post")
            // Calibrated grid: first cell is camera, second is the newest photo.
            try ui.point(160, 705)
            try ui.visual(journal.state.marker) // Must see the unique marker on the selected image.
            try ui.visual("Next", tap: true)
        }
        if !inCaption && !inCaptionEditor {
            try ui.visual("Filter")
            try ui.visual(journal.state.marker)
            // OCR includes the arrow in “Next →”; this calibrated button is guarded by the editor page.
            try ui.point(377, 860)
        }
        if (try? ui.has("Sharing posts")) == true { try ui.visual("OK", tap: true) }
        if !inCaptionEditor { try ui.visual("Add a caption...", tap: true) }
        try ui.visual("Caption")
        try ui.clearAndType(caption)
        try ui.point(388, 81) // Caption editor's checkmark has no accessible text.
        try ui.visual("Share")
        try ui.visual(journal.state.marker)
    }
    func publish() throws {
        try ui.visual("Share")
        try journal.checkpoint()
        try ui.visual("Share", tap: true)
        try ui.wait(id: "mainfeed-tab")
    }
    func verify() throws {
        try Login(ui: ui, journal: journal).profile()
        try ui.wait(id: "media-thumbnail-cell", tap: true, index: 0)
        try ui.wait("Posts. " + journal.state.account)
        try ui.wait(journal.state.account + " " + caption)
        for _ in 0..<4 {
            if try ui.words().contains(where: { $0.0 == journal.state.marker }) { break }
            try ui.socket.call("input.swipe", ["x1": 215, "y1": 320, "x2": 215, "y2": 800, "seconds": 0.4])
            Thread.sleep(forTimeInterval: 0.6)
        }
        try ui.visual(journal.state.marker)
        try ui.image().write(to: journal.directory.appendingPathComponent("published.jpg"), options: .atomic)
    }
}
#endif
