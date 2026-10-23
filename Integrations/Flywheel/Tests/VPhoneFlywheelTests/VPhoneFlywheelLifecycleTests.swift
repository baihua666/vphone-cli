import Foundation
import Testing
@testable import VPhoneFlywheel

@Suite @MainActor
struct VPhoneFlywheelLifecycleTests {
    private func temporary(_ body: (URL, VPhoneFlywheelDeviceStore) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try VPhoneFlywheelDeviceStore(url: root.appendingPathComponent("business/devices.store"))
        try body(root, store)
    }

    private func reference(_ url: URL, udid: String? = "same-udid") -> VPhoneFlywheelMachineReference {
        .init(libraryRoot: url.deletingLastPathComponent().path, name: url.lastPathComponent, udid: udid,
              directoryIdentity: VPhoneFlywheelMachineReference.directoryIdentity(at: url))
    }

    @Test func cloneThenDeleteSourceNeverTransfersBusinessRecord() throws {
        try temporary { root, store in
            let source = root.appendingPathComponent("source")
            let clone = root.appendingPathComponent("clone")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try Data("platform fixture".utf8).write(to: source.appendingPathComponent("config.plist"))
            let original = reference(source)
            try store.save(number: "1", machine: original, region: "US", notes: "source notes")
            try FileManager.default.copyItem(at: source, to: clone)
            let cloned = reference(clone)
            #expect(original.directoryIdentity != cloned.directoryIdentity)
            #expect(original.udid == cloned.udid)
            try store.synchronizeMachines([original, cloned])
            #expect(store.devices.count == 1) // No automatic business row for a clone.
            try FileManager.default.removeItem(at: source)
            try store.synchronizeMachines([cloned])
            #expect(store.devices.first?.machine == original)
            #expect(!original.matches(cloned)) // UI and actions cannot resolve it to the clone.
            #expect(store.devices.first?.notes == "source notes")
            let reopened = try VPhoneFlywheelDeviceStore(url: store.url)
            try reopened.synchronizeMachines([cloned])
            #expect(reopened.devices.first?.machine == original)
        }
    }

    @Test func sameNameReplacementWithSameUDIDDoesNotMatch() throws {
        try temporary { root, store in
            let source = root.appendingPathComponent("source")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            let original = reference(source)
            try store.save(number: "1", machine: original, region: "US", notes: "keep")
            // Retain the original elsewhere so this also covers restore/replacement.
            try FileManager.default.moveItem(at: source, to: root.appendingPathComponent("retired"))
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            let replacement = reference(source)
            try store.synchronizeMachines([replacement])
            #expect(!original.matches(replacement))
            #expect(store.devices.first?.machine == original)
        }
    }

    @Test func cloneCanBeExplicitlyBoundAndRenamedIndependently() throws {
        try temporary { root, store in
            let source = root.appendingPathComponent("source")
            let clone = root.appendingPathComponent("clone")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: clone)
            let firstID = try store.save(number: "1", machine: reference(source), region: "US", notes: "first")
            let secondID = try store.save(number: "2", machine: reference(clone), region: "JP", notes: "second")
            let renamed = root.appendingPathComponent("renamed")
            try FileManager.default.moveItem(at: clone, to: renamed)
            try store.synchronizeMachines([reference(source), reference(renamed)])
            #expect(store.devices.first { $0.id == firstID }?.machine.name == "source")
            #expect(store.devices.first { $0.id == secondID }?.machine.name == "renamed")
            #expect(store.devices.first { $0.id == secondID }?.region == "JP")
            try FileManager.default.removeItem(at: renamed)
            try store.synchronizeMachines([reference(source)])
            #expect(store.devices.count == 2) // Platform deletion never removes business metadata.
            #expect(store.devices.first { $0.id == secondID }?.notes == "second")
        }
    }

    @Test func newIdentityCloneAcquiresUDIDWithoutLosingBinding() throws {
        try temporary { root, store in
            let clone = root.appendingPathComponent("clone")
            try FileManager.default.createDirectory(at: clone, withIntermediateDirectories: true)
            let id = try store.save(number: "2", machine: reference(clone, udid: nil), region: "", notes: "new")
            try store.synchronizeMachines([reference(clone, udid: "generated-on-first-boot")])
            #expect(store.devices.first?.id == id)
            #expect(store.devices.first?.machine.udid == "generated-on-first-boot")
        }
    }

    @Test func legacyReferenceRequiresExplicitConfirmation() throws {
        try temporary { root, store in
            let source = root.appendingPathComponent("source")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            let legacy = VPhoneFlywheelMachineReference(libraryRoot: root.path, name: "source", udid: "same-udid")
            let id = try store.save(number: "1", machine: legacy, region: "US", notes: "legacy")
            try store.synchronizeMachines([reference(source)])
            #expect(store.devices.first?.machine.directoryIdentity == nil)
            #expect(!legacy.matches(reference(source)))
            try store.save(id: id, number: "1", machine: reference(source), region: "US", notes: "legacy")
            #expect(store.devices.first?.machine.matches(reference(source)) == true)
        }
    }
}
