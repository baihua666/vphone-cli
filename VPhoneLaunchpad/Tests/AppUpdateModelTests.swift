import Foundation
import VPhoneDistribution

// Only error presentation belongs to the application; the model otherwise uses real distribution types.
enum VPhoneLaunchpadError {
    static func message(for error: Error) -> String { error.localizedDescription }
}

actor UpdateFetchCount {
    var value = 0
    func increment() { value += 1 }
}

@main @MainActor struct AppUpdateModelTests {
    static func idle(_ model: VPhoneLaunchpadAppUpdateModel) async throws {
        for _ in 0..<500 {
            if !model.busy { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        fatalError("update check did not finish")
    }

    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let report = directory.appendingPathComponent("error.txt")
        try "previous installation failed".write(to: report, atomically: true, encoding: .utf8)
        let catalog = try DistributionCatalog.decode(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let count = UpdateFetchCount()
        let updates = VPhoneLaunchpadAppUpdateModel(report: report) {
            await count.increment()
            try await Task.sleep(for: .milliseconds(40))
            return [catalog]
        }
        precondition(updates.error == "previous installation failed")
        precondition(!FileManager.default.fileExists(atPath: report.path))
        updates.check()
        updates.check()
        precondition(updates.busy && updates.error.isEmpty)
        try await idle(updates)
        let calls = await count.value
        precondition(calls == 1 && updates.hasAppUpdate && updates.catalog?.tag == catalog.tag)

        let failed = VPhoneLaunchpadAppUpdateModel(report: report) { throw DistributionError("offline") }
        failed.catalog = catalog
        failed.check()
        try await idle(failed)
        precondition(failed.catalog == nil && !failed.hasAppUpdate && failed.error.contains("offline"))
        precondition(updates.catalog?.tag == catalog.tag && updates.error.isEmpty)

        let empty = VPhoneLaunchpadAppUpdateModel(report: report) { [] }
        empty.check()
        try await idle(empty)
        precondition(!empty.hasAppUpdate && empty.error.isEmpty && empty.status.contains("尚无"))
        print("PASS: independent App checks, duplicate check, stale result rejection, errors and installation report")
    }
}
