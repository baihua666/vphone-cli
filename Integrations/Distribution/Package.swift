// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "VPhoneDistribution", platforms: [.macOS(.v15)], products: [
    .library(name: "VPhoneDistribution", targets: ["VPhoneDistribution"]),
    .executable(name: "distribution-publisher", targets: ["DistributionPublisher"]),
], targets: [
    .target(name: "VPhoneDistribution"),
    .executableTarget(name: "DistributionPublisher", dependencies: ["VPhoneDistribution"]),
    .testTarget(name: "VPhoneDistributionTests", dependencies: ["VPhoneDistribution"]),
])
