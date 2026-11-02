import Foundation
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION && VPHONE_CUSTOM_THREADS_AUTOMATION
struct ThreadsSession {
    let ui: Screen
    let journal: RunJournal
    func launch() throws {
        try ui.socket.call("apps.launch", ["bundle_id": "com.burbn.barcelona"])
        Thread.sleep(forTimeInterval: 2)
        var ready = false
        for _ in 0..<60 {
            if let elements = try? ui.tree(), elements.contains(where: {
                ["Profile", "Password", "Log in with Instagram", "Add this to your Instagram story",
                 "Share your threads to your Instagram story", "Manage", "Photos", "New thread",
                 "Save login info?", "Save your login info?", "Log out of your account?", "Unable to log in"].contains($0["label"] as? String ?? "")
            }) { ready = true; break }
            Thread.sleep(forTimeInterval: 1)
        }
        guard ready else { throw Failure("Threads 启动后的界面尚未就绪") }
        if (try? ui.has("Add this to your Instagram story")) == true { try ui.wait("Not now", tap: true) }
        try dismissSharingHint()
    }
    func dismissSharingHint() throws {
        if (try? ui.has("Share your threads to your Instagram story")) == true {
            try ui.socket.call("input.swipe", ["x1": 215, "y1": 625, "x2": 215, "y2": 910, "seconds": 0.5])
            Thread.sleep(forTimeInterval: 1)
        }
    }
    func profile() throws {
        try dismissSharingHint()
        if journal.state.bioChanged {
            if try ui.has("Edit bio") { try ui.wait("Cancel", tap: true) }
            if try ui.has(id: "done-button"), try ui.has("Edit profile") { try ui.wait("Cancel", tap: true) }
            if try ui.has("Discard changes") { try ui.wait("Discard changes", tap: true) }
        }
        try ui.wait("Profile", tap: true)
        // Profile keeps its previous scroll position. Bring identity and Edit profile into view.
        for _ in 0..<5 {
            if try ui.has(journal.state.account), let edit = try ui.tree().first(where: { $0["label"] as? String == "Edit profile" }),
               let frame = edit["frame"] as? [String: Double], (frame["y"] ?? -1) > 50 { break }
            try ui.socket.call("input.swipe", ["x1": 215, "y1": 300, "x2": 215, "y2": 780, "seconds": 0.4])
            Thread.sleep(forTimeInterval: 0.6)
        }
        try ui.wait("Edit profile", tap: true)
        try ui.wait("Username: " + journal.state.account)
        try ui.wait("Cancel", tap: true)
        try ui.wait("Profile")
    }
    func login(password: String?) throws {
        if try ui.has("Profile") {
            try profile()
            if !journal.state.freshLogin || journal.state.loginSubmitted {
                try journal.event("session", "reused")
                return
            }
            try ui.wait("Settings", tap: true)
            for _ in 0..<10 {
                if try ui.has("Log out") { break }
                try ui.swipeUp()
                Thread.sleep(forTimeInterval: 0.7)
            }
            try ui.wait("Log out", tap: true)
        }
        for _ in 0..<90 {
            if journal.state.loginSubmitted { break }
            if (try? ui.has("Save login info?")) == true { try ui.wait("Don't save", tap: true) }
            else if (try? ui.has("Log out of your account?")) == true { try ui.wait("Log out", tap: true) }
            else if (try? ui.has("Password")) == true || (try? ui.has(id: "single-user-login-card")) == true { break }
            Thread.sleep(forTimeInterval: 1)
        }
        if !journal.state.loginSubmitted {
            // The card becomes accessible before its logout transition is interactive.
            // Retry only opening this form, never submitting credentials.
            for _ in 0..<3 {
                if try ui.has("Password") { break }
                if try ui.has(id: "single-user-login-card") {
                    Thread.sleep(forTimeInterval: 1)
                    try ui.wait(id: "single-user-login-card", tap: true)
                }
                for _ in 0..<10 {
                    if (try? ui.has("Password")) == true { break }
                    Thread.sleep(forTimeInterval: 1)
                }
            }
            try ui.wait("Password")
            let secret = try password ?? Credentials.read(journal.state.account)
            let label = "Username, email or mobile number"
            guard let field = try ui.tree().first(where: { $0["label"] as? String == label }),
                  let frame = field["frame"] as? [String: Double], let y = frame["y"] else { throw Failure("Threads 用户名字段不可用") }
            try ui.point(180, y + 25)
            try ui.clearAndType(journal.state.account)
            try ui.wait("Password", tap: true)
            try ui.wait("Show password")
            try ui.clearAndType("")
            try ui.socket.call("input.type", ["text": secret, "delay_ms": 100])
            let fields = try ui.tree()
            guard fields.first(where: { $0["label"] as? String == label })?["value"] as? String == journal.state.account,
                  (fields.first(where: { $0["label"] as? String == "Password" })?["value"] as? String)?.count == secret.count else {
                try ui.clearAndType(""); throw Failure("Threads 登录字段核验失败，未提交")
            }
            journal.state.loginSubmitted = true
            try journal.save()
            try ui.wait("Log in", tap: true)
        }
        for _ in 0..<60 {
            if (try? ui.has("Unable to log in")) == true {
                try ui.image().write(to: journal.directory.appendingPathComponent("login-error.jpg"), options: .atomic)
                journal.state.loginSubmitted = false
                try journal.save()
                try ui.wait("OK", tap: true)
                throw Failure("Threads 明确返回登录失败；已保留证据，可沿用原命令重试")
            }
            if (try? ui.has("Save your login info?")) == true {
                try ui.wait("Not now", tap: true)
                continue
            }
            if try ui.has("Profile") { try profile(); return }
            let words = try ui.tree().compactMap { $0["label"] as? String }.joined(separator: " ")
            if Login.isChallenge(words) {
                try journal.event("login", "needs_verification")
                print("请在虚拟机完成 Threads 验证，然后沿用原命令续跑。")
                throw VerificationRequired()
            }
            Thread.sleep(forTimeInterval: 1)
        }
        throw Failure("Threads 登录未完成；保留现场，不重复提交密码")
    }
    static func bio(from elements: [[String: Any]]) throws -> String {
        let labels = elements.compactMap { $0["label"] as? String }.filter { $0.hasPrefix("Bio: ") }
        guard labels.count == 1 else { throw Failure("Threads 简介字段不唯一") }
        let value = String(labels[0].dropFirst(5))
        return value == "+ Write bio" ? "" : value
    }
    func openBio() throws -> String {
        try profile()
        try ui.wait("Edit profile", tap: true)
        try ui.wait("Username: " + journal.state.account)
        return try Self.bio(from: ui.tree())
    }
    func writeBio(current: String, new: String) throws {
        try ui.wait("Bio: " + (current.isEmpty ? "+ Write bio" : current), tap: true)
        try ui.wait(current.isEmpty ? "Write a bio…" : current, tap: true)
        try ui.clearAndType("")
        if !new.isEmpty { try ui.socket.call("input.type", ["text": new, "delay_ms": 100]) }
        try ui.wait(id: "done-button", tap: true)
        try ui.wait("Bio: " + (new.isEmpty ? "+ Write bio" : new))
        try ui.wait(id: "done-button", tap: true)
        try ui.wait("Profile")
    }
    func restoreBio() throws {
        guard let original = journal.state.originalBio else { throw Failure("缺少简介备份") }
        let current = try openBio()
        guard current == original || current == journal.state.marker else { throw Failure("简介被其他操作修改，停止覆盖") }
        if current != original { try writeBio(current: current, new: original) }
        else { try ui.wait("Cancel", tap: true) }
        let restored = try openBio()
        guard restored == original else { throw Failure("简介恢复读回不匹配") }
        try ui.wait("Cancel", tap: true)
        journal.state.bioChanged = false
        try journal.save()
    }
    func testProfile() throws {
        if journal.state.bioChanged { try restoreBio() }
        let original = try openBio()
        journal.state.originalBio = original
        journal.state.bioChanged = true
        try journal.save()
        try writeBio(current: original, new: journal.state.marker)
        try ui.wait(journal.state.marker)
        try restoreBio()
    }
}
#endif
