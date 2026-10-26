// swift-tools-version: 6.0
import PackageDescription

// Clear to retain the legacy search-only Decodo location selector.
let decodoLocationSettings: [SwiftSetting] = [.define("VPHONE_CUSTOM_DECODO_LOCATION_BROWSING")]

let package = Package(
    name: "vphone-ws",
    platforms: [.macOS(.v15)],
    products: [.library(name: "VPhoneWSCore", targets: ["VPhoneWSCore"])],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", exact: "6.1.0")],
    targets: [
        .target(name: "VPhoneWSCore", dependencies: ["Yams"], path: "Sources/VPhoneWSCore",
                swiftSettings: decodoLocationSettings),
        .executableTarget(
            name: "vphone-ws",
            dependencies: ["VPhoneWSCore"],
            path: "Sources/vphone-ws"),
        .testTarget(
            name: "VPhoneWSCoreTests",
            dependencies: ["VPhoneWSCore"],
            path: "tests/VPhoneWSCoreTests", swiftSettings: decodoLocationSettings),
    ]
)
