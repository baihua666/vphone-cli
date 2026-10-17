// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vphone-ws",
    platforms: [.macOS(.v15)],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", exact: "6.1.0")],
    targets: [
        .target(name: "VPhoneWSCore", dependencies: ["Yams"], path: "Sources/VPhoneWSCore"),
        .executableTarget(
            name: "vphone-ws",
            dependencies: ["VPhoneWSCore"],
            path: "Sources/vphone-ws"),
        .testTarget(
            name: "VPhoneWSCoreTests",
            dependencies: ["VPhoneWSCore"],
            path: "tests/VPhoneWSCoreTests"),
    ]
)
