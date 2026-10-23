// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VPhoneFlywheel",
    platforms: [.macOS(.v15)],
    products: [.library(name: "VPhoneFlywheel", targets: ["VPhoneFlywheel"])],
    targets: [
        .target(name: "VPhoneFlywheel"),
        .testTarget(name: "VPhoneFlywheelTests", dependencies: ["VPhoneFlywheel"]),
    ]
)
