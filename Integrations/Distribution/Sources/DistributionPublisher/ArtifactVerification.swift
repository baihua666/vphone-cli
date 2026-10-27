import Foundation
import CryptoKit
import VPhoneDistribution

func command(_ executable: String, _ arguments: [String]) throws -> Data {
    let process = Process(); let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
    process.standardOutput = pipe; process.standardError = FileHandle.standardError
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw DistributionError("校验命令失败：\(URL(fileURLWithPath: executable).lastPathComponent)") }
    return data
}
func verifyArtifacts(dmg: URL, core: URL, baseline: String, revision: Int, coreVersion: String, signing: DistributionSigning) throws {
    if signing == .notarized { _ = try command("/usr/bin/xcrun", ["stapler", "validate", dmg.path]) }
    let mount = FileManager.default.temporaryDirectory.appendingPathComponent("vphone-release-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
    // Only remove a mount point after successful detach; never traverse a mounted image.
    _ = try command("/usr/bin/hdiutil", ["attach", dmg.path, "-readonly", "-nobrowse", "-mountpoint", mount.path])
    defer {
        if (try? command("/usr/bin/hdiutil", ["detach", mount.path])) != nil { try? FileManager.default.removeItem(at: mount) }
    }
    let app = mount.appendingPathComponent("vphone-launchpad.app")
    if FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Resources/DecodoPrivateDefaults").path) {
        // Public account distribution requires approval of this exact signed
        // installer; an approval must not authorize a different future build.
        guard let approved = ProcessInfo.processInfo.environment["VPHONE_APPROVED_ACCOUNT_DMG_SHA256"],
              try DistributionDownload.digest(dmg) == approved else {
            throw DistributionError("安装包含私有 Decodo 账号，禁止上传公开发行；用户明确批准后须用 VPHONE_APPROVED_ACCOUNT_DMG_SHA256 指定该包的精确 SHA-256。")
        }
    }
    _ = try command("/usr/bin/codesign", ["--verify", "--strict", "--deep", "-R=anchor apple generic and identifier com.vphone.launchpad", app.path])
    if signing == .notarized { _ = try command("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path]) }
    // Keep SMJobBless mutual trust intact for both distribution modes.
    let helper = app.appendingPathComponent("Contents/Library/LaunchServices/com.vphone.launchpad.helper")
    let requirement = try command("/usr/libexec/PlistBuddy", ["-c", "Print :SMPrivilegedExecutables:com.vphone.launchpad.helper", app.appendingPathComponent("Contents/Info.plist").path])
    let rule = String(decoding: requirement, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    _ = try command("/usr/bin/codesign", ["--verify", "--strict", "-R=" + rule, helper.path])

    let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any]
    guard info?["CFBundleShortVersionString"] as? String == baseline,
          info?["VPhoneDistributionRevision"] as? String == String(revision) else {
        throw DistributionError("DMG 中 App 基线或发布修订与目录不一致")
    }
    let expectedMode = signing.rawValue
    guard (info?["VPhoneDistributionSigning"] as? String ?? "notarized") == expectedMode else {
        throw DistributionError("App 签名分发模式与目录不一致")
    }
    let coreInfo = try command("/usr/bin/unzip", ["-p", core.path, "VPhone.bundle/Contents/Info.plist"])
    let corePlist = try PropertyListSerialization.propertyList(from: coreInfo, format: nil) as? [String: Any]
    let seal = try command("/usr/bin/unzip", ["-p", core.path, "VPhone.bundle/Contents/_CodeSignature/CodeResources"])
    let hash = SHA256.hash(data: seal).prefix(4).map { String(format: "%02x", $0) }.joined()
    guard !seal.isEmpty, corePlist?["CFBundleShortVersionString"] as? String == baseline,
          coreVersion == baseline + "-local." + hash else {
        throw DistributionError("Core seal 身份与目录不一致")
    }
}
func verifyDirectory(_ folder: URL) throws {
    let catalog = try DistributionCatalog.decode(Data(contentsOf: folder.appendingPathComponent(GitHubDistribution.manifestName)))
    try DistributionPublicationPolicy.validate(catalog, names: FileManager.default.contentsOfDirectory(atPath: folder.path))
    for asset in catalog.assets {
        guard try DistributionDownload.matches(folder.appendingPathComponent(asset.name), bytes: asset.size, digest: asset.sha256) else {
            throw DistributionError("发布附件校验失败：\(asset.name)")
        }
    }
    let allowed = Set(catalog.assets.map(\.name) + [GitHubDistribution.manifestName, "release-notes.md"])
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    guard names.allSatisfy({ allowed.contains($0) }) else { throw DistributionError("发布目录含未登记文件，拒绝批量上传") }
    try verifyArtifacts(dmg: folder.appendingPathComponent(catalog.app.asset.name), core: folder.appendingPathComponent(catalog.core.asset.name),
                        baseline: catalog.app.baseline, revision: catalog.app.revision, coreVersion: catalog.core.version, signing: catalog.app.signingMode)
    print("发布目录附件、App 签名模式及修订、Core seal 校验通过")
}
