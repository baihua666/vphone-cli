import Foundation
import Testing
@testable import VPhoneFlywheel

@Suite @MainActor
struct VPhoneFlywheelDeviceStoreTests {
    private func temporary(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func machine(_ name: String = "phone", root: String = "/machines", udid: String? = "UDID-1") -> VPhoneFlywheelMachineReference {
        .init(libraryRoot: root, name: name, udid: udid)
    }

    @Test func durableCRUDAndSQLiteStore() throws {
        try temporary { directory in
            let url = directory.appendingPathComponent("devices.store")
            let id = try autoreleasepool {
                let store = try VPhoneFlywheelDeviceStore(url: url)
                #expect(store.devices.isEmpty)
                return try store.save(number: "001", machine: machine(), region: "us", notes: "first")
            }
            try autoreleasepool {
                let reopened = try VPhoneFlywheelDeviceStore(url: url)
                let device = try #require(reopened.devices.first)
                #expect(device.id == id)
                #expect(device.number == "1")
                #expect(device.region == "US")
                #expect(device.machine == machine())
                try reopened.save(id: id, number: "2", machine: machine(), region: "JP", notes: "updated")
            }
            try autoreleasepool {
                let reopened = try VPhoneFlywheelDeviceStore(url: url)
                #expect(reopened.devices.count == 1)
                #expect(reopened.devices.first?.number == "2")
                #expect(reopened.devices.first?.notes == "updated")
                try reopened.delete(id: id)
            }
            #expect(try VPhoneFlywheelDeviceStore(url: url).devices.isEmpty)
            let header = try Data(contentsOf: url).prefix(16)
            #expect(String(decoding: header, as: UTF8.self) == "SQLite format 3\0")
        }
    }

    @Test func rejectsDuplicateNumbersAndBindingsWithoutChangingSavedData() throws {
        try temporary { directory in
            let store = try VPhoneFlywheelDeviceStore(url: directory.appendingPathComponent("devices.store"))
            try store.save(number: "7", machine: machine(), region: "", notes: "original")
            #expect(throws: VPhoneFlywheelError.self) {
                try store.save(number: "0007", machine: machine("other"), region: "US", notes: "duplicate")
            }
            #expect(throws: VPhoneFlywheelError.self) {
                try store.save(number: "8", machine: machine(), region: "US", notes: "duplicate")
            }
            try store.reload()
            #expect(store.devices.count == 1)
            #expect(store.devices.first?.notes == "original")
        }
    }

    @Test func failedEditLeavesOriginalRecordIntact() throws {
        try temporary { directory in
            let store = try VPhoneFlywheelDeviceStore(url: directory.appendingPathComponent("devices.store"))
            let id = try store.save(number: "1", machine: machine(), region: "US", notes: "keep")
            try store.save(number: "2", machine: machine("other"), region: "JP", notes: "other")
            #expect(throws: VPhoneFlywheelError.self) {
                try store.save(id: id, number: "2", machine: machine(), region: "GB", notes: "must not save")
            }
            #expect(throws: VPhoneFlywheelError.self) {
                try store.save(id: id, number: "3", machine: machine(), region: "invalid", notes: "must not save")
            }
            try store.reload()
            let device = try #require(store.devices.first { $0.id == id })
            #expect(device.number == "1" && device.region == "US" && device.notes == "keep")
        }
    }

    @Test func sameNamesInDifferentLibrariesRemainDistinct() throws {
        try temporary { directory in
            let store = try VPhoneFlywheelDeviceStore(url: directory.appendingPathComponent("devices.store"))
            let first = machine(root: "/library-a")
            let second = machine(root: "/library-b")
            try store.save(number: "1", machine: first, region: "US", notes: "")
            try store.save(number: "2", machine: second, region: "JP", notes: "")
            #expect(store.devices.count == 2)
            #expect(!first.matches(second))
            #expect(!first.matches(machine(root: "/library-a", udid: "replacement")))
            #expect(!first.matches(machine("renamed", root: "/library-a")))
            #expect(!first.matches(machine(root: "/library-a", udid: nil)))
            #expect(first.matches(first))
        }
    }

    @Test func explicitRebindingPreservesBusinessIdentity() throws {
        try temporary { directory in
            let store = try VPhoneFlywheelDeviceStore(url: directory.appendingPathComponent("devices.store"))
            let id = try store.save(number: "9", machine: machine(), region: "US", notes: "keep")
            try store.save(id: id, number: "9", machine: machine("renamed"), region: "US", notes: "keep")
            #expect(store.devices.first?.id == id)
            #expect(store.devices.first?.machine.name == "renamed")
        }
    }

    @Test func validationAcceptsOnlyASCIIDigitsAndSortsNumerically() throws {
        for value in ["", "-1", "+1", "1.0", "1e3", "１", "١", "1 2", "a"] {
            #expect(throws: VPhoneFlywheelError.self) { try VPhoneFlywheelValidation.number(value) }
        }
        #expect(try VPhoneFlywheelValidation.number(" 000 ") == "0")
        try temporary { directory in
            let store = try VPhoneFlywheelDeviceStore(url: directory.appendingPathComponent("devices.store"))
            for number in ["10", "999999999999999999999999999999999", "2"] {
                try store.save(number: number, machine: machine(number), region: "", notes: "")
            }
            #expect(store.devices.map(\.number) == ["2", "10", "999999999999999999999999999999999"])
        }
    }

    @Test func rejectsStaleWritesAndInvalidMachineLocators() throws {
        try temporary { directory in
            let store = try VPhoneFlywheelDeviceStore(url: directory.appendingPathComponent("devices.store"))
            #expect(throws: VPhoneFlywheelError.self) { try store.delete(id: UUID()) }
            #expect(throws: VPhoneFlywheelError.self) {
                try store.save(id: UUID(), number: "1", machine: machine(), region: "", notes: "")
            }
            for invalid in [machine(".."), machine("a/b"), machine(root: "relative")] {
                #expect(throws: VPhoneFlywheelError.self) {
                    try store.save(number: "1", machine: invalid, region: "", notes: "")
                }
            }
            #expect(store.devices.isEmpty)
        }
    }

    @Test func independentStoresAndSearch() throws {
        try temporary { directory in
            let first = try VPhoneFlywheelDeviceStore(url: directory.appendingPathComponent("a/devices.store"))
            let second = try VPhoneFlywheelDeviceStore(url: directory.appendingPathComponent("b/devices.store"))
            try first.save(number: "1", machine: machine(), region: "US", notes: "运营设备")
            #expect(second.devices.isEmpty)
            let device = try #require(first.devices.first)
            for query in ["1", "PHONE", "us", "运营", "  "] { #expect(device.matches(search: query)) }
            #expect(!device.matches(search: "JP"))
        }
    }

    @Test func deletingBusinessRecordDoesNotTouchMachineFiles() throws {
        try temporary { directory in
            let vm = directory.appendingPathComponent("machines/phone")
            try FileManager.default.createDirectory(at: vm, withIntermediateDirectories: true)
            let file = vm.appendingPathComponent("launchpad.json")
            let bytes = Data("original platform configuration".utf8)
            try bytes.write(to: file)
            let store = try VPhoneFlywheelDeviceStore(url: directory.appendingPathComponent("business/devices.store"))
            let id = try store.save(number: "1", machine: machine(root: vm.deletingLastPathComponent().path), region: "", notes: "")
            try store.delete(id: id)
            #expect(try Data(contentsOf: file) == bytes)
        }
    }

    @Test func unreadableStoreFailsWithoutResettingItsContents() throws {
        try temporary { directory in
            let url = directory.appendingPathComponent("broken.store")
            let bytes = Data("not a database".utf8)
            try bytes.write(to: url)
            #expect(throws: (any Error).self) { try VPhoneFlywheelDeviceStore(url: url) }
            #expect(try Data(contentsOf: url) == bytes)
            #expect(throws: (any Error).self) {
                try VPhoneFlywheelDeviceStore(url: url.appendingPathComponent("devices.store"))
            }
        }
    }
}
