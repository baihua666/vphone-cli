import XCTest
@testable import VPhoneDistribution

final class ReleaseRetentionTests: XCTestCase {
    private func executeScript(history: String = "[]", verification: Int = 0, latest: String = "launchpad-new") throws -> (Int32, String) {
        let root = try DistributionTests().temp()
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let log = root.appendingPathComponent("deleted")
        let gh = #"""
        #!/bin/zsh
        set -eu
        if [[ "$1 $2" == 'release download' ]]; then
          dest="${@: -1}"
          print -r -- '{"tag":"launchpad-new","previousTags":'"$TEST_HISTORY"',"images":[]}' > "$dest/launchpad-catalog.json"
        elif [[ "$1 $2" == 'release delete' ]]; then
          print -r -- "$3" >> "$TEST_LOG"
        elif [[ "$1" == api ]]; then
          if [[ "$2" == --paginate ]]; then
            print -l launchpad-new launchpad-old unrelated-release
          else
            print -r -- "$TEST_LATEST"
          fi
        else
          exit 90
        fi
        """#
        for (name, content) in [("gh", gh), ("swift", "#!/bin/zsh\nexit $TEST_VERIFY\n")] {
            let file = bin.appendingPathComponent(name)
            try Data(content.utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/prune-releases.zsh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path, "launchpad-new"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = bin.path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        env["TMPDIR"] = root.path
        env["TEST_HISTORY"] = history
        env["TEST_VERIFY"] = String(verification)
        env["TEST_LATEST"] = latest
        env["TEST_LOG"] = log.path
        process.environment = env
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError
        try process.run(); process.waitUntilExit()
        let deleted = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        return (process.terminationStatus, deleted)
    }
    func testOnlyOldProductReleaseRemovedAfterVerification() throws {
        let result = try executeScript()
        XCTAssertEqual(result.0, 0)
        XCTAssertEqual(result.1, "launchpad-old\n")
    }
    func testNoDeletionWhenDownloadsFailOrCatalogReferencesHistoryOrLatestDiffers() throws {
        for result in [try executeScript(verification: 1), try executeScript(history: "[\"launchpad-old\"]"), try executeScript(latest: "launchpad-other")] {
            XCTAssertNotEqual(result.0, 0)
            XCTAssertEqual(result.1, "")
        }
    }
}
