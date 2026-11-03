import Foundation
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION
struct ProfileTest {
    let ui: Screen
    let journal: RunJournal
    func run() throws {
        try ui.wait(journal.state.account, id: "user-switch-title-button")
        try ui.wait("Edit profile", tap: true)
        try ui.wait(id: "profile-bio")
        if journal.state.originalBio == nil {
            let element = try ui.tree().first { $0["identifier"] as? String == "profile-bio" }
            journal.state.originalBio = element?["value"] as? String ?? ""
            try journal.save()
        }
        try ui.wait(id: "profile-bio", tap: true)
        try ui.wait("Write a profile bio", tap: true)
        journal.state.bioChanged = true
        try journal.save()
        try ui.clearAndType(journal.state.marker)
        try saveAndBack()
        try ui.wait(journal.state.marker)
        try restore()
    }
    func restore() throws {
        guard journal.state.bioChanged, let original = journal.state.originalBio else { return }
        try ui.wait("Edit profile", tap: true)
        try ui.wait(id: "profile-bio", tap: true)
        try ui.wait("Write a profile bio", tap: true)
        try ui.clearAndType(original)
        try saveAndBack()
        if original.isEmpty {
            try ui.socket.call("ui.wait_gone", ["text": journal.state.marker, "match": "exact", "timeout": 20])
        } else { try ui.wait(original) }
        journal.state.bioChanged = false
        try journal.save()
    }
    private func saveAndBack() throws {
        let done = try ui.tree().first { $0["identifier"] as? String == "done-button" }
        // A resumed restoration may already have saved the original value.
        if done?["enabled"] as? Bool == false {
            try ui.wait(id: "BackButton", tap: true)
        } else { try ui.wait(id: "done-button", tap: true) }
        try ui.wait(id: "profile-user-name")
        for _ in 0..<3 {
            if try ui.has(id: "user-switch-title-button") {
                try ui.wait(journal.state.account, id: "user-switch-title-button")
                return
            }
            try ui.wait(id: "profile-user-name")
            try ui.wait(id: "BackButton", tap: true)
            for _ in 0..<10 {
                if (try? ui.has(id: "user-switch-title-button")) == true { break }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        try ui.wait(journal.state.account, id: "user-switch-title-button")
    }
}
#endif
