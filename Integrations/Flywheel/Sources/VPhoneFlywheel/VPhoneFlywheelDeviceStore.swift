import Foundation
import Observation
import SwiftData

@MainActor
@Observable
public final class VPhoneFlywheelDeviceStore {
    public private(set) var devices: [VPhoneFlywheelDevice] = []
    public let url: URL
    private let container: ModelContainer
    private let context: ModelContext

    public static var defaultURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("vphone-launchpad/Flywheel", isDirectory: true)
            .appendingPathComponent("devices.store")
    }

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let schema = Schema([VPhoneFlywheelDeviceRecord.self])
        let configuration = ModelConfiguration("FlywheelDevices", schema: schema, url: url, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false
        try reload()
    }

    public func reload() throws {
        devices = try records().map(\.device).sorted {
            if $0.number.count != $1.number.count { return $0.number.count < $1.number.count }
            return $0.number < $1.number
        }
    }

    /// All validation happens before mutating SwiftData. Failed saves roll back.
    @discardableResult
    public func save(
        id: UUID? = nil, number: String, machine: VPhoneFlywheelMachineReference, region: String, notes: String
    ) throws -> UUID {
        let number = try VPhoneFlywheelValidation.number(number)
        let region = try VPhoneFlywheelValidation.region(region)
        guard machine.libraryRoot.hasPrefix("/"), !machine.name.isEmpty,
              !machine.name.contains("/"), machine.name != ".", machine.name != ".." else {
            throw VPhoneFlywheelError("虚拟机关联无效，请重新选择平台实例。")
        }
        let records = try records()
        let existing = records.first { $0.id == id }
        if id != nil && existing == nil { throw VPhoneFlywheelError("业务记录已不存在，请刷新列表。") }
        guard !records.contains(where: { $0.id != id && $0.number == number }) else {
            throw VPhoneFlywheelError("设备编号 \(number) 已存在。")
        }
        guard !records.contains(where: { $0.id != id && $0.machinePath == machine.id }) else {
            throw VPhoneFlywheelError("该虚拟机已关联业务设备，请编辑已有记录。")
        }
        let record = existing ?? VPhoneFlywheelDeviceRecord(
            id: UUID(), number: number, machine: machine, region: region, notes: notes
        )
        if existing == nil { context.insert(record) }
        record.number = number
        record.machinePath = machine.id
        record.libraryRoot = machine.libraryRoot
        record.machineName = machine.name
        record.machineUDID = machine.udid
        record.directoryIdentity = machine.directoryIdentity
        record.region = region
        record.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedID = record.id
        try commit()
        return savedID
    }

    /// Reconcile platform renames without changing business identity or metadata.
    /// Never infer a rename from UDID: ordinary platform clones preserve it.
    public func synchronizeMachines(_ machines: [VPhoneFlywheelMachineReference]) throws {
        let records = try records()
        var changed = false
        for record in records {
            let old = record.device.machine
            guard !machines.contains(where: { old.matches($0) }),
                  let identity = old.directoryIdentity, !identity.isEmpty else { continue }
            let candidates = machines.filter {
                $0.libraryRoot == old.libraryRoot && $0.directoryIdentity == identity
                    && (old.udid == $0.udid || old.udid == nil)
            }
            guard candidates.count == 1, let current = candidates.first,
                  records.filter({ $0.libraryRoot == old.libraryRoot && $0.directoryIdentity == identity }).count == 1,
                  !records.contains(where: { $0.id != record.id && $0.machinePath == current.id }) else { continue }
            record.machineName = current.name
            record.machinePath = current.id
            record.machineUDID = current.udid
            changed = true
        }
        if changed { try commit() }
    }

    public func delete(id: UUID) throws {
        guard let record = try records().first(where: { $0.id == id }) else {
            throw VPhoneFlywheelError("业务记录已不存在，请刷新列表。")
        }
        context.delete(record)
        try commit()
    }

    private func records() throws -> [VPhoneFlywheelDeviceRecord] {
        try context.fetch(FetchDescriptor<VPhoneFlywheelDeviceRecord>())
    }

    private func commit() throws {
        do { try context.save() } catch {
            context.rollback()
            throw error
        }
        try reload()
    }
}
