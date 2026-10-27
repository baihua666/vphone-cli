// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Clear to retain the legacy search-only Decodo location selector.
let decodoLocationSettings: [SwiftSetting] = [.define("VPHONE_CUSTOM_DECODO_LOCATION_BROWSING")]
// Existing native-proxy UI opts into the tested-endpoint save workflow. Set to 1 to build the legacy path.
let nativeProxyWorkflowSettings: [SwiftSetting] = ProcessInfo.processInfo.environment["VPHONE_DISABLE_NATIVE_PROXY_WORKFLOW"] == "1"
    ? [] : [.define("VPHONE_CUSTOM_NATIVE_PROXY_WORKFLOW")]

// Disable to build the legacy file-based credential path.
let embeddedDecodoSettings: [SwiftSetting] = ProcessInfo.processInfo.environment["VPHONE_DISABLE_EMBEDDED_DECODO_CREDENTIALS"] == "1"
    ? [] : [.define("VPHONE_CUSTOM_EMBEDDED_DECODO_CREDENTIALS")]

let package = Package(
    name: "vphone-ws",
    platforms: [.macOS(.v15)],
    products: [.library(name: "VPhoneWSCore", targets: ["VPhoneWSCore"])],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", exact: "6.1.0")],
    targets: [
        .target(name: "VPhoneWSCore", dependencies: ["Yams"], path: "Sources/VPhoneWSCore",
                swiftSettings: decodoLocationSettings + nativeProxyWorkflowSettings + embeddedDecodoSettings),
        .executableTarget(
            name: "vphone-ws",
            dependencies: ["VPhoneWSCore"],
            path: "Sources/vphone-ws"),
        .testTarget(
            name: "VPhoneWSCoreTests",
            dependencies: ["VPhoneWSCore"],
            path: "tests/VPhoneWSCoreTests", swiftSettings: decodoLocationSettings + nativeProxyWorkflowSettings + embeddedDecodoSettings),
    ]
)
