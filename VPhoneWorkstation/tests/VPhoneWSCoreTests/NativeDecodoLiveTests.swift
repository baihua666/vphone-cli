import Foundation
import Testing
@testable import VPhoneWSCore

/// Opt-in, real guest acceptance of the exact controller used by Launchpad's buttons.
/// Only independently created test machines are accepted. Never starts/stops a VM or edits Clash.
@Test(.enabled(if: ProcessInfo.processInfo.environment["VPHONE_NATIVE_VM_LIVE"] == "1"))
@MainActor func nativeDecodoTwoGuestRotationAndClashFallback() async throws {
    let env = ProcessInfo.processInfo.environment
    let executable = try #require(env["VPHONE_NATIVE_VM_CLI"])
    let root = try #require(env["VPHONE_NATIVE_VM_ROOT"])
    let credentials = try #require(env["VPHONE_NATIVE_VM_CREDENTIALS"])
    let names = ["native-https-test-a", "native-https-test-b"]
    let client = VPhoneCLIClient(executable: URL(fileURLWithPath: executable), libraryRoot: root, runner: SystemCLIRunner())
    let controllers = names.map { NativeDecodoController(client: client, name: $0) }
    for controller in controllers {
        controller.credentialsPath = credentials
        controller.device = env["VPHONE_NATIVE_VM_DEVICE"] ?? "en1"
        controller.interface = env["VPHONE_NATIVE_VM_INTERFACE"] ?? "wifi"
        await controller.refresh()
        try #require(controller.supported)
    }
    // On any assertion/error, explicitly restore only these test machines.
    do {
        var ips: [String] = []
        for controller in controllers {
            await controller.rotate()
            let ip = try #require(controller.guestIP, Comment(rawValue: controller.message))
            try #require(controller.enabled)
            try #require(controller.location?.ip == ip, Comment(rawValue: controller.message))
            ips.append(ip)
        }
        print("LIVE initial: A=\(ips[0]), B=\(ips[1])")
        try #require(ips[0] != ips[1])
        await controllers[0].rotate()
        let rotated = try #require(controllers[0].guestIP, Comment(rawValue: controllers[0].message))
        await controllers[1].detectGuest()
        print("LIVE rotate A: A=\(rotated), B=\(controllers[1].guestIP ?? "missing")")
        try #require(rotated != ips[0])
        try #require(controllers[1].guestIP == ips[1])
        await controllers[0].restoreClash()
        await controllers[0].detectGuest()
        await controllers[1].detectGuest()
        let fallback = try #require(controllers[0].guestIP)
        print("LIVE restore A: A=\(fallback), B=\(controllers[1].guestIP ?? "missing")")
        try #require(!controllers[0].enabled)
        try #require(controllers[1].guestIP == ips[1])
        await controllers[1].restoreClash()
        await controllers[1].detectGuest()
        print("LIVE restore B: B=\(controllers[1].guestIP ?? "missing")")
        try #require(!controllers[1].enabled)
        try #require(controllers[1].guestIP != nil)
    } catch {
        for controller in controllers { await controller.restoreClash() }
        throw error
    }
}

/// Explicit opt-in: caller supplies two stopped/idle machines reserved for this acceptance run.
/// Leaves successful routes configured so restart persistence can be verified separately.
@Test(.enabled(if: ProcessInfo.processInfo.environment["VPHONE_NATIVE_REGIONS_LIVE"] == "1"))
@MainActor func nativeRegionsTwoGuestRotation() async throws {
    let env = ProcessInfo.processInfo.environment
    let names = try #require(env["VPHONE_NATIVE_REGIONS_MACHINES"]).split(separator: ",").map(String.init)
    try #require(names.count == 2 && Set(names).count == 2)
    let root = try #require(env["VPHONE_NATIVE_VM_ROOT"])
    let store = URL(fileURLWithPath: try #require(env["VPHONE_NATIVE_VM_STORE"]))
    let client = VPhoneCLIClient(executable: store, libraryRoot: root, runner: SystemCLIRunner(), launchpadStore: store)
    let catalog = try await DecodoLocations.fetch()
    let city = try #require(catalog.first { $0.kind == .city && $0.country == "US" && $0.city == "New York City" })
    let values = names.map { NativeDecodoController(client: client, name: $0) }
    for value in values {
        await value.refresh(); try #require(value.supported)
        await value.rotate(location: city)
        try #require(value.enabled && value.guestIP != nil && value.guestIP == value.location?.ip, Comment(rawValue: value.message))
        try #require(value.configuredLocation(in: catalog) == city)
    }
    let first = try #require(values[0].guestIP), second = try #require(values[1].guestIP)
    try #require(first != second)
    let secondReference = URL(fileURLWithPath: root).appendingPathComponent(names[1]).appendingPathComponent("native-proxy-reference.json")
    let before = try Data(contentsOf: secondReference)
    await values[0].rotate(location: city)
    await values[1].detectGuest()
    try #require(values[0].guestIP != nil && values[0].guestIP != first, Comment(rawValue: values[0].message))
    try #require(values[1].guestIP == second)
    #expect(try Data(contentsOf: secondReference) == before)
    print("LIVE regions initial A=\(first), B=\(second); rotated A=\(values[0].guestIP!), B=\(values[1].guestIP!)")
}
