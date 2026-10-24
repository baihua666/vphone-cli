import Foundation

/// Image revisions are independent of App revisions. Keep the owning release
/// so an old image always downloads its own parts and compatible Core.
public struct DistributionImageVersion: Identifiable, Sendable {
    public let image: DistributionImage
    public let catalog: DistributionCatalog
    public var id: String { "\(image.id):\(image.revision)" }

    public static func all(in catalogs: [DistributionCatalog]) -> [Self] {
        var seen = Set<String>()
        return catalogs.flatMap { catalog in
            catalog.images.map { Self(image: $0, catalog: catalog) }
        }.filter { seen.insert($0.id).inserted }.sorted {
            if $0.image.id != $1.image.id { return $0.image.id < $1.image.id }
            return $0.image.revision > $1.image.revision
        }
    }
}
