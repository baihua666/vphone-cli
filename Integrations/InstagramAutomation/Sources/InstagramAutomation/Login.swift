import Foundation
import Darwin
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION
struct VerificationRequired: Error {}
struct Login {
    let ui: Screen
    let journal: RunJournal
    var suppliedPassword: String? = nil
    func profile() throws {
        for _ in 0..<8 {
            if journal.state.bioChanged, try ui.has("Discard changes") {
                try ui.wait("Discard changes", tap: true)
                continue
            }
            if try ui.has(id: "profile-tab") {
                try ui.wait(id: "profile-tab", tap: true)
                try ui.wait(journal.state.account, id: "user-switch-title-button")
                return
            }
            if try ui.has(id: "BackButton") { try ui.wait(id: "BackButton", tap: true) }
            else { Thread.sleep(forTimeInterval: 1) }
        }
        throw Failure("无法返回指定账号主页")
    }
    func run() throws {
        var password = suppliedPassword
        try ui.socket.call("apps.launch", ["bundle_id": "com.burbn.instagram"])
        Thread.sleep(forTimeInterval: 2)
        if !journal.state.loginSubmitted,
           (try? ui.has(id: "profile-tab")) == true || (try? ui.has(id: "BackButton")) == true {
            try profile()
            if !journal.state.freshLogin && journal.state.passwordLogin != true { return }
            if password == nil { password = try Credentials.read(journal.state.account) }
            if journal.state.freshLogin { try logout() }
            else {
                try ui.wait(id: "user-switch-title-button", tap: true)
                try ui.wait("Add Instagram account", tap: true)
                try ui.wait("Log in to existing account", tap: true)
                try openAccountForm()
            }
        }
        if !journal.state.loginSubmitted {
            if (try? ui.has("Log into another account")) == true { try ui.wait("Log into another account", tap: true) }
            if (try? ui.has("Use another profile")) == true { try ui.wait("Use another profile", tap: true) }
            try ui.wait("Password")
            try enterCredentials(password: password ?? Credentials.read(journal.state.account))
            journal.state.loginSubmitted = true
            try journal.save() // Never blindly submit the password again on resume.
            try journal.event("password-submit", "started")
            try ui.visual("Log in", tap: true)
        }
        try awaitResult()
    }
    private func openAccountForm() throws {
        var refreshed = false
        for _ in 0..<90 {
            if (try? ui.has("Use another profile")) == true {
                try ui.wait("Use another profile", tap: true)
                return
            }
            if (try? ui.has("Password")) == true { return }
            if !refreshed, (try? ui.has("Refresh")) == true {
                try ui.wait("Refresh", tap: true)
                refreshed = true
            }
            Thread.sleep(forTimeInterval: 1)
        }
        throw Failure("Instagram 登录入口未加载；保留现场，不重复提交密码")
    }
    private func enterCredentials(password: String) throws {
        let usernameLabel = "Username, email or mobile number"
        guard let user = try ui.tree().first(where: { $0["label"] as? String == usernameLabel }),
              let frame = user["frame"] as? [String: Double], let y = frame["y"] else {
            throw Failure("用户名输入框未匹配")
        }
        // Bloks exposes the floating label, whose center is not the editable area.
        try ui.point(180, y + 25)
        try ui.clearAndType(journal.state.account)
        try ui.wait(id: "Next:", tap: true)
        try ui.wait("Show password") // Appears only after the secure field has focus.
        try ui.clearAndType(password)
        let fields = try ui.tree()
        guard fields.first(where: { $0["label"] as? String == usernameLabel })?["value"] as? String == journal.state.account,
              (fields.first(where: { $0["label"] as? String == "Password" })?["value"] as? String)?.count == password.count else {
            try ui.clearAndType("")
            throw Failure("输入字段核验失败，已清空当前字段，未提交密码")
        }
    }
    func logout() throws {
        try ui.wait(id: "profile-more-button", tap: true)
        try ui.wait("Settings and activity")
        for _ in 0..<16 {
            if try ui.words().contains(where: { $0.0 == "Log out" }) {
                try ui.visual("Log out", tap: true)
                Thread.sleep(forTimeInterval: 1)
                if (try? ui.has("Not now")) == true { try ui.wait("Not now", tap: true) }
                if (try? ui.has("Log out")) == true { try ui.wait("Log out", tap: true) }
                return
            }
            try ui.swipeUp()
            Thread.sleep(forTimeInterval: 1)
        }
        throw Failure("设置页未加载退出入口；未退出账号")
    }
    func awaitResult() throws {
        for _ in 0..<30 {
            if (try? ui.has(id: "profile-tab")) == true { try profile(); return }
            if (try? ui.has("Not now")) == true { try ui.wait("Not now", tap: true) }
            let text = (try? ui.words().map(\.0).joined(separator: " ").lowercased()) ?? ""
            if ["incorrect password", "password was incorrect", "try again later", "suspended"].contains(where: text.contains) {
                throw Failure("Instagram 拒绝登录；请核对账号或页面提示，不自动重试密码")
            }
            if Self.isChallenge(text) { try verification(); return }
            Thread.sleep(forTimeInterval: 1)
        }
        throw Failure("登录结果等待超时；保留现场，修复网络或完成人工验证后用原命令续跑")
    }
    static func isChallenge(_ text: String) -> Bool {
        ["security code", "confirmation code", "authentication code", "check your notifications",
         "confirm it's you", "confirm your identity", "captcha", "6-digit code"].contains(where: text.lowercased().contains)
    }
    private func verification() throws {
        try journal.event("login", "needs_verification")
        print("需要 Instagram 验证：在同账号已登录设备批准，或在虚拟机输入验证码。完成后沿用原命令续跑。")
        guard isatty(STDIN_FILENO) == 1 else { throw VerificationRequired() }
        print("若页面是验证码输入框，可在此隐藏输入验证码；若已在设备完成验证，输入 done：")
        let code = try Credentials.hiddenInput("验证码 / done: ")
        if code != "done" {
            guard (6...8).contains(code.count), code.allSatisfy(\.isNumber) else { throw Failure("验证码格式不正确") }
            let fields = try ui.tree().filter { element in
                let label = (element["label"] as? String ?? "").lowercased()
                return label.contains("code") && ["textField", "textfield"].contains(element["role"] as? String ?? "")
            }
            guard fields.count == 1 else { throw Failure("验证码框无法唯一定位，请直接在虚拟机完成验证后续跑") }
            try fill(fields[0], text: code)
            try ui.visual("Continue", tap: true)
        }
        // One verification attempt per invocation; never repeatedly prompt or resend codes.
        for _ in 0..<30 {
            if (try? ui.has(id: "profile-tab")) == true { try profile(); return }
            Thread.sleep(forTimeInterval: 1)
        }
        throw VerificationRequired()
    }
    private func fill(_ field: [String: Any], text: String) throws {
        guard let frame = field["frame"] as? [String: Double], let x = frame["x"], let y = frame["y"],
              let width = frame["width"], let height = frame["height"], width > 20, height > 10 else {
            throw Failure("输入框坐标不可用")
        }
        try ui.point(x + width / 2, y + height / 2)
        try ui.clearAndType(text)
    }
}
#endif
