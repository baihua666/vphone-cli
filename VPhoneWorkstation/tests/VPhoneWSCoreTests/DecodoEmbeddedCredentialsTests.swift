import Foundation
import Testing
@testable import VPhoneWSCore

@MainActor @Test func nativeCredentialsHaveNoMachineFileDependencyWhenEmbedded() throws {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    #if VPHONE_CUSTOM_EMBEDDED_DECODO_CREDENTIALS
    #expect(NativeDecodoController.usesEmbeddedCredentials)
    let credentials = try NativeDecodoService.credentials(path: missing)
    // Only booleans enter failure diagnostics, never account values.
    #expect(!credentials.username.isEmpty)
    #expect(!credentials.password.isEmpty)
    let otherMac = try NativeDecodoService.credentials(path: "/Users/another-mac/no-credentials.json")
    let identical = credentials == otherMac
    #expect(identical)
    #else
    #expect(!NativeDecodoController.usesEmbeddedCredentials)
    #expect(throws: (any Error).self) { try NativeDecodoService.credentials(path: missing) }
    #endif
}
