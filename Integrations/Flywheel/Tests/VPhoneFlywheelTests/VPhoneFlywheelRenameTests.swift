import Foundation
import Testing
@testable import VPhoneFlywheel

@Suite @MainActor
struct VPhoneFlywheelRenameTests {
    private func machine(_ name: String, root: String = "/machines", udid: String? = "unique", identity: String? = "directory-1") -> VPhoneFlywheelMachineReference {
        .init(libraryRoot: root, name: name, udid: udid, directoryIdentity: identity)
    }

    private func temporary(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("devices.store"))
    }

    @Test func renamePreservesBusinessDataAndSurvivesReopening() throws {
        try temporary { url in
            let renamed = machine("new-name")
            let id = try autoreleasepool {
                let store = try VPhoneFlywheelDeviceStore(url: url)
                let id = try store.save(number: "17", machine: machine("old-name"), region: "US", notes: "keep notes")
                try store.synchronizeMachines([renamed])
                let device = try #require(store.devices.first)
                #expect(device.id == id && device.number == "17")
                #expect(device.region == "US" && device.notes == "keep notes")
                #expect(device.machine == renamed)
                #expect(device.matches(search: "new-name"))
                #expect(!device.matches(search: "old-name"))
                #expect(device.machine.matches(renamed)) // Host action locator is now current.
                #expect(throws: VPhoneFlywheelError.self) {
                    try store.save(number: "18", machine: renamed, region: "", notes: "")
                }
                try store.synchronizeMachines([renamed])
                return id
            }
            let reopened = try VPhoneFlywheelDeviceStore(url: url)
            #expect(reopened.devices.first?.id == id)
            #expect(reopened.devices.first?.machine == renamed)
            try reopened.synchronizeMachines([machine("third-name")])
            #expect(reopened.devices.first?.machine.name == "third-name")
        }
    }

    @Test func missingAmbiguousOrChangedIdentityDoesNotRebind() throws {
        let cases: [(VPhoneFlywheelMachineReference, [VPhoneFlywheelMachineReference])] = [
            (machine("old"), []),
            (machine("old"), [machine("new", root: "/other-library")]),
            (machine("old"), [machine("old", udid: "replacement")]),
            (machine("old"), [machine("new"), machine("clone")]),
            (machine("old", udid: nil, identity: nil), [machine("new", udid: nil, identity: nil)]),
            (machine("old", udid: "", identity: nil), [machine("new", udid: "", identity: nil)]),
        ]
        for (original, current) in cases {
            try temporary { url in
                let store = try VPhoneFlywheelDeviceStore(url: url)
                try store.save(number: "1", machine: original, region: "", notes: "keep")
                try store.synchronizeMachines(current)
                #expect(store.devices.first?.machine == original)
            }
        }
    }

    @Test func occupiedTargetAndDuplicateBusinessIdentitiesAreNotMerged() throws {
        for duplicateUDID in [false, true] {
            try temporary { url in
                let store = try VPhoneFlywheelDeviceStore(url: url)
                try store.save(number: "1", machine: machine("old"), region: "", notes: "first")
                try store.save(number: "2", machine: machine("new", udid: duplicateUDID ? "unique" : "other"), region: "", notes: "second")
                let original = store.devices
                try store.synchronizeMachines([machine("new")])
                #expect(store.devices == original)
            }
        }
    }
}
