import Foundation
import ThreadsDesktop
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION && VPHONE_CUSTOM_THREADS_AUTOMATION
enum ThreadsWorkflow {
    static func run(socket: String, directory: URL, freshLogin: Bool, password: String?, request: ThreadsTaskRequest? = nil) throws {
        let journal = try RunJournal(directory: directory, socket: socket, account: request?.account ?? "test409518",
                                     freshLogin: freshLogin, platform: "threads")
        if let request { try ThreadsTaskBinding.bind(request, journal: journal) }
        if journal.state.completed.contains("verify") { print("Threads 此任务已完成，未重复发帖"); return }
        try ThreadsRestriction.check(directory: directory)
        let ui = Screen(socket: GuestSocket(path: socket), inspect: { try ThreadsRestriction.inspect($0, directory: directory) })
        let screen = try ui.socket.request("device.screen", [:])
        guard screen["width"] as? Int == 430, screen["height"] as? Int == 932,
              screen["orientation"] as? Int == 0 else { throw Failure("Threads 仅校准了 430×932 竖屏") }
        let session = ThreadsSession(ui: ui, journal: journal)
        let post = ThreadsPost(ui: ui, journal: journal, customCaption: request?.publishedCaption)
        // A rejected login can leave the embedded form stale. Reopen only before
        // a new attempt; never restart an unknown in-flight login or publication.
        if journal.state.completed.isEmpty && !journal.state.loginSubmitted && !journal.state.publishAttempted {
            try ui.socket.call("apps.terminate", ["bundle_id": "com.burbn.barcelona"])
        }
        try session.launch()
        if journal.state.publishAttempted {
            try journal.stage("verify") { try post.verify() }
            return
        }
        try journal.stage("login") { try session.login(password: password) }
        if request == nil || request?.testProfile == true || journal.state.bioChanged {
            try journal.stage("profile") { try session.testProfile() }
        }
        let image = directory.appendingPathComponent("fixture.png")
        try journal.stage("import") {
            if request == nil { try Fixture.create(marker: journal.state.marker, at: image, title: "Threads automation", markerSize: 80, barcode: true) }
            try MediaImport(ui: ui).run(image: image, marker: journal.state.marker)
        }
        try session.launch()
        // Recheck the actual draft on every resume, even if preparation was previously complete.
        try journal.event("prepare", "started")
        try post.prepare()
        try journal.event("prepare", "passed")
        try journal.stage("publish") { try post.publish() }
        try journal.stage("verify") { try post.verify() }
        print("Threads 一键测试完成；报告: \(directory.path)")
    }
}
#endif
