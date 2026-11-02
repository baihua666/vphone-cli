// swift-tools-version: 6.0
import PackageDescription
import Foundation
let enabled = ProcessInfo.processInfo.environment["VPHONE_CUSTOM_INSTAGRAM_AUTOMATION"] == "1"
let threadsEnabled = ProcessInfo.processInfo.environment["VPHONE_CUSTOM_THREADS_AUTOMATION"] == "1"
let settings: [SwiftSetting] = (enabled ? [.define("VPHONE_CUSTOM_INSTAGRAM_AUTOMATION")] : [])
    + (threadsEnabled ? [.define("VPHONE_CUSTOM_THREADS_AUTOMATION")] : [])
let desktopSettings: [SwiftSetting] = ProcessInfo.processInfo.environment["VPHONE_THREADS_DESKTOP_DISABLED"] == "1" ? [] : [.define("VPHONE_CUSTOM_THREADS_DESKTOP")]
let package = Package(name: "InstagramAutomation", platforms: [.macOS(.v15)],
    products: [.library(name: "ThreadsDesktop", targets: ["ThreadsDesktop"]), .executable(name: "instagram-test", targets: ["InstagramAutomation"])],
    targets: [.target(name: "ThreadsDesktop", swiftSettings: desktopSettings), .testTarget(name: "ThreadsDesktopTests", dependencies: ["ThreadsDesktop"], swiftSettings: desktopSettings),
              .executableTarget(name: "InstagramAutomation", dependencies: ["ThreadsDesktop"], swiftSettings: settings),
              .testTarget(name: "InstagramAutomationTests", dependencies: ["InstagramAutomation"], swiftSettings: settings)])
