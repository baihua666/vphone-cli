import Foundation
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION
enum Workflow {
    static func run(socket: String, directory: URL, freshLogin: Bool, password: String? = nil, passwordLogin: Bool = false) throws {
        let journal = try RunJournal(directory: directory, socket: socket, account: "test409518",
                                     freshLogin: freshLogin, passwordLogin: passwordLogin)
        let ui = Screen(socket: GuestSocket(path: socket))
        let login = Login(ui: ui, journal: journal, suppliedPassword: password)
        let post = PostTest(ui: ui, journal: journal)
        if journal.state.completed.contains("verify") { print("此任务已完成，未重复发帖"); return }
        if journal.state.publishAttempted {
            try journal.stage("verify") { try post.verify() }
            return
        }
        try journal.stage("login") { try login.run() }
        try journal.stage("profile") {
            try login.profile()
            let profile = ProfileTest(ui: ui, journal: journal)
            if journal.state.bioChanged { try profile.restore() }
            try profile.run()
        }
        let image = directory.appendingPathComponent("fixture.png")
        try journal.stage("import") {
            try Fixture.create(marker: journal.state.marker, at: image)
            try MediaImport(ui: ui).run(image: image, marker: journal.state.marker)
        }
        try ui.socket.call("apps.launch", ["bundle_id": "com.burbn.instagram"])
        Thread.sleep(forTimeInterval: 2)
        try journal.stage("prepare") { try post.prepare() }
        try journal.stage("publish") { try post.publish() }
        try journal.stage("verify") { try post.verify() }
        print("一键测试完成；报告: \(directory.path)")
    }
}
#endif
