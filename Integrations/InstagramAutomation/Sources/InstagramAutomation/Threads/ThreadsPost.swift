import Foundation
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION && VPHONE_CUSTOM_THREADS_AUTOMATION
struct ThreadsPost {
    let ui: Screen
    let journal: RunJournal
    var customCaption: String? = nil
    var includesImage = true
    static func attachmentCount(_ elements: [[String: Any]]) -> Int {
        let old = elements.filter { ($0["label"] as? String ?? "").hasPrefix("Remove photo at attached item #") }
        if !old.isEmpty { return old.count }
        guard elements.contains(where: { $0["label"] as? String == "Remove media" }) else { return 0 }
        return elements.filter { $0["identifier"] as? String == "image-view" }.count
    }
    func hasPhoto() throws -> Bool { try Self.attachmentCount(ui.tree()) > 0 }
    func waitForSinglePhoto() throws {
        for _ in 0..<90 {
            let count = try Self.attachmentCount(ui.tree())
            if count == 1 { return }
            guard count == 0 else { throw Failure("草稿包含多张图片，停止发布") }
            Thread.sleep(forTimeInterval: 1)
        }
        throw Failure("未发现唯一图片附件")
    }
    var caption: String { customCaption ?? journal.state.marker + "\nAutomated test. Generated image; no personal content." }
    func prepare() throws {
        if includesImage {
        if try !ui.has("Manage") && !ui.has(id: "Update") && !ui.has("Select more photos") {
            if !(try ui.has(id: "composer-text-view")) {
                try ThreadsSession(ui: ui, journal: journal).profile()
                try ui.wait("Create post", tap: true)
            }
            try ui.wait(journal.state.account)
            if !(try hasPhoto()) {
                try ui.wait("Add photos and videos from your camera roll", tap: true)
            }
        }
        if !(try hasPhoto()) {
            if try ui.has("Manage") {
                try ui.wait("Manage", tap: true)
                try ui.wait("Select more photos")
            }
            if try ui.has("Select more photos") {
                try ui.wait("Select more photos", tap: true)
                try ui.wait(id: "Update")
            }
            if try ui.has(id: "Update") {
                try PhotoSelection(ui: ui).grant(marker: journal.state.marker)
                try ui.socket.call("ui.wait_gone", ["identifier": "Update", "match": "exact", "timeout": 30])
                try ui.wait("Manage")
            }
            try ui.wait("Done")
            try ui.waitMarker(journal.state.marker)
            // Locate the unique marker's actual photo cell; never assume newest is cell zero.
            let matches = try ui.markerMatches(journal.state.marker)
            guard matches.count == 1, let rect = matches.first?.1 else { throw Failure("测试图编号不唯一") }
            let point = CGPoint(x: rect.midX * 430, y: (1 - rect.midY) * 932)
            let cells = try ui.tree().filter { item in
                guard (item["identifier"] as? String ?? "").hasPrefix("grid-view-cell-"),
                      let frame = item["frame"] as? [String: Double], let x = frame["x"], let y = frame["y"],
                      let w = frame["width"], let h = frame["height"] else { return false }
                return CGRect(x: x, y: y, width: w, height: h).contains(point)
            }
            guard cells.count == 1, let id = cells[0]["identifier"] as? String else { throw Failure("测试图无法对应唯一格子") }
            if (cells[0]["traits"] as? UInt64 ?? 0) & 8 == 0 { try ui.wait(id: id, tap: true) }
            try ui.wait("Done", tap: true)
        }
        try ui.wait(id: "composer-text-view")
        try ui.wait(journal.state.account)
        try waitForSinglePhoto()
        guard !(try ui.has("Remove photo at attached item #2")) else { throw Failure("草稿包含多张图片，停止发布") }
        } else {
            if !(try ui.has(id: "composer-text-view")) {
                try ThreadsSession(ui: ui, journal: journal).profile()
                try ui.wait("Create post", tap: true)
            }
            try ui.wait(journal.state.account)
            try ui.wait(id: "composer-text-view")
            guard !(try hasPhoto()) else { throw Failure("纯文字任务发现已有图片草稿，停止覆盖") }
        }
        let draft = try ui.tree().first(where: { $0["identifier"] as? String == "composer-text-view" })
        let text = draft?["label"] as? String ?? ""
        guard text == "What’s new?" || text.isEmpty || text.hasPrefix(journal.state.marker) else {
            throw Failure("已有不属于本任务的草稿，停止覆盖")
        }
        // Clear caption before OCR so the marker can only come from the attached image.
        try ui.wait(id: "composer-text-view", tap: true)
        try ui.clearAndType("")
        if includesImage { try ui.waitMarker(journal.state.marker) }
        try ui.socket.call("input.type", ["text": caption, "delay_ms": 100])
        try ui.wait(caption)
        try ui.wait(id: "composer-post-button")
    }
    func publish() throws {
        try ui.wait(journal.state.account)
        try ui.wait(caption)
        if includesImage { try waitForSinglePhoto() }
        else { guard !(try hasPhoto()) else { throw Failure("纯文字任务包含意外附件，停止发布") } }
        try journal.checkpoint()
        try ui.wait(id: "composer-post-button", tap: true)
        try ui.wait("Profile")
    }
    static func markerIsInImage(words: [(String, CGRect)], marker: String, captionFrame: CGRect) -> Bool {
        let matches = words.filter { $0.0 == marker }.map(\.1).sorted { $0.midY > $1.midY }
        // Use the same screenshot for both coordinates: AX frames can shift during scrolling.
        return matches.count == 2 && matches[0].minY > matches[1].maxY + 0.02
            && words.contains { $0.0 == "Threads automation" }
    }
    func verify() throws {
        let session = ThreadsSession(ui: ui, journal: journal)
        // The profile can show an optimistic local post while upload is still pending.
        for attempt in 0..<90 {
            let words = try ui.tree().compactMap { ($0["label"] as? String)?.lowercased() }
            if words.contains(where: { $0.contains("posting") }) {
                guard attempt < 89 else { throw Failure("Threads 仍在上传，禁止重复发布") }
                Thread.sleep(forTimeInterval: 1)
            } else { break }
        }
        try ui.socket.call("apps.terminate", ["bundle_id": "com.burbn.barcelona"])
        try session.launch()
        if try ui.has("Add this to your Instagram story") { try ui.wait("Not now", tap: true) }
        try session.profile()
        for _ in 0..<40 {
            let elements = try ui.tree()
            if let captionElement = elements.first(where: { $0["label"] as? String == caption }),
               let frame = captionElement["frame"] as? [String: Double],
               let x = frame["x"], let y = frame["y"], let w = frame["width"], let h = frame["height"],
               try ui.has(journal.state.account) {
                if !includesImage {
                    try ui.image().write(to: journal.directory.appendingPathComponent("published.jpg"), options: .atomic)
                    return
                }
                let barcodeFound = try ui.codes().filter({ $0.0 == journal.state.marker }).count == 1
                if try barcodeFound || Self.markerIsInImage(words: ui.words(), marker: journal.state.marker,
                                        captionFrame: CGRect(x: x, y: y, width: w, height: h)) {
                    try ui.image().write(to: journal.directory.appendingPathComponent("published.jpg"), options: .atomic)
                    return
                }
                if y > 60 && y < 330 {
                    Thread.sleep(forTimeInterval: 2) // Hold the post in view while its remote image loads.
                    continue
                }
            }
            try ui.socket.call("input.swipe", ["x1": 215, "y1": 650, "x2": 215, "y2": 550, "seconds": 0.8])
            Thread.sleep(forTimeInterval: 0.8)
        }
        throw Failure("未同时核实本任务全文与图片内编号；禁止重复发布，请核对后原目录续跑")
    }
}
#endif
