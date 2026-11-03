// swift-tools-version: 6.0
import PackageDescription
import Foundation
let enabled = ProcessInfo.processInfo.environment["VPHONE_CUSTOM_INSTAGRAM_AUTOMATION"] == "1"
let threadsEnabled = ProcessInfo.processInfo.environment["VPHONE_CUSTOM_THREADS_AUTOMATION"] == "1"
let photoSettings: [SwiftSetting] = ProcessInfo.processInfo.environment["VPHONE_PHOTO_SELECTION_DISABLED"] == "1" ? [] : [.define("VPHONE_CUSTOM_PHOTO_SELECTION")]
let settings: [SwiftSetting] = (enabled ? [.define("VPHONE_CUSTOM_INSTAGRAM_AUTOMATION")] : [])
    + (threadsEnabled ? [.define("VPHONE_CUSTOM_THREADS_AUTOMATION")] : [])
let desktopSettings: [SwiftSetting] = ProcessInfo.processInfo.environment["VPHONE_THREADS_DESKTOP_DISABLED"] == "1" ? [] : [.define("VPHONE_CUSTOM_THREADS_DESKTOP")]
let package = Package(name: "InstagramAutomation", platforms: [.macOS(.v15)],
    products: [.library(name: "PhotoPicker", targets: ["PhotoPicker"]), .library(name: "ThreadsDesktop", targets: ["ThreadsDesktop"]), .executable(name: "instagram-test", targets: ["InstagramAutomation"])],
    targets: [.target(name: "ThreadsDesktop", swiftSettings: desktopSettings), .testTarget(name: "ThreadsDesktopTests", dependencies: ["ThreadsDesktop"], swiftSettings: desktopSettings),
              .target(name: "PhotoPicker", swiftSettings: photoSettings),
              .testTarget(name: "PhotoPickerTests", dependencies: ["PhotoPicker"], swiftSettings: photoSettings),
              .executableTarget(name: "InstagramAutomation", dependencies: ["ThreadsDesktop", "PhotoPicker"], swiftSettings: settings),
              .testTarget(name: "InstagramAutomationTests", dependencies: ["InstagramAutomation"], swiftSettings: settings)])
