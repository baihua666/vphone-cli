// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "VPhoneApplicationManagement", platforms: [.macOS(.v15)],
    products: [.library(name: "VPhoneApplicationManagement", targets: ["VPhoneApplicationManagement"])],
    targets: [.target(name: "VPhoneApplicationManagement"),
              .testTarget(name: "VPhoneApplicationManagementTests", dependencies: ["VPhoneApplicationManagement"])])
