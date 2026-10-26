import Foundation
import CryptoKit
import VPhoneDistribution

struct Recipe: Decodable {
    let previousTags: [String]?
    let tag: String
    let baseline: String
    let appRevision: Int
    let signing: DistributionSigning?
    let minimumMacOS: Int
    let appDMG: String
    let coreVersion: String
    let coreZIP: String
    let images: [Image]
    struct Image: Decodable {
        let id: String
        let version: String
        let revision: Int
        let title: String
        let archive: String
        let expandedBytes: Int64
    }
}
func object<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
}
func record(_ file: URL) throws -> DistributionAsset {
    let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize!
    return try DistributionAsset(name: file.lastPathComponent, size: Int64(size), sha256: DistributionDownload.digest(file))
}
func copy(_ path: String, as name: String, to output: URL) throws -> DistributionAsset {
    let destination = output.appendingPathComponent(name)
    try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: destination)
    let result = try record(destination)
    try result.validate()
    return result
}
func main() async throws {
    let args = CommandLine.arguments
    if args.count >= 2 && args[1] == "--check-download" {
        guard args.count == 3 else { throw DistributionError("用法：distribution-publisher --check-download 新缓存目录；镜像仅由本地目录管理") }
        try await checkDownload(URL(fileURLWithPath: args[2]))
        return
    }

    if args.count == 3 && args[1] == "--verify" { try verifyDirectory(URL(fileURLWithPath: args[2])); return }
    guard args.count == 3 else { throw DistributionError("用法：distribution-publisher recipe.json 新的输出目录") }
    let recipe = try JSONDecoder().decode(Recipe.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
    guard recipe.images.isEmpty, (recipe.previousTags ?? []).isEmpty else { throw DistributionError("禁止上传镜像；请在本地镜像目录管理，发布 recipe 的 images 和 previousTags 必须为空。") }
    guard DistributionAsset.safeName(recipe.tag), recipe.appRevision > 0,
          recipe.images.allSatisfy({ $0.expandedBytes > 0 && $0.expandedBytes < Int64.max / 8 && $0.revision > 0 && !$0.title.isEmpty && DistributionAsset.safeName($0.id + "-" + String($0.revision) + ".part0000") && DistributionAsset.safeName($0.version) }),
          Set(recipe.images.map(\.id)).count == recipe.images.count else { throw DistributionError("发布参数无效") }
    try verifyArtifacts(dmg: URL(fileURLWithPath: recipe.appDMG), core: URL(fileURLWithPath: recipe.coreZIP), baseline: recipe.baseline, revision: recipe.appRevision, coreVersion: recipe.coreVersion, signing: recipe.signing ?? .notarized)
    let output = URL(fileURLWithPath: args[2], isDirectory: true)
    guard !FileManager.default.fileExists(atPath: output.path) else { throw DistributionError("输出目录已存在，不会覆盖") }
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let app = try copy(recipe.appDMG, as: "vphone-launchpad-\(recipe.tag).dmg", to: output)
    let core = try copy(recipe.coreZIP, as: "VPhone-\(recipe.coreVersion).zip", to: output)
    let catalog: [String: Any] = ["schema": 1, "tag": recipe.tag, "previousTags": recipe.previousTags ?? [],
        "app": ["baseline": recipe.baseline, "revision": recipe.appRevision, "minimumMacOS": recipe.minimumMacOS, "signing": (recipe.signing ?? .notarized).rawValue, "asset": try object(app)],
        "core": ["version": recipe.coreVersion, "asset": try object(core)], "images": [Any]()]
    let data = try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
    _ = try DistributionCatalog.decode(data)
    try data.write(to: output.appendingPathComponent(GitHubDistribution.manifestName), options: .atomic)
    print("已生成并校验发布目录：\(output.path)；未上传。发布前核对签名模式、Core seal 和镜像清洁性。")
}
do { try await main() } catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1)
}
