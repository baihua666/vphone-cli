import Foundation
import SwiftData

/// Kept internal so UI editing cannot bypass validation or explicit saves.
@Model
final class VPhoneFlywheelDeviceRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var number: String
    @Attribute(.unique) var machinePath: String
    var libraryRoot: String
    var machineName: String
    var machineUDID: String?
    var directoryIdentity: String?
    var region: String
    var notes: String

    init(id: UUID, number: String, machine: VPhoneFlywheelMachineReference, region: String, notes: String) {
        self.id = id
        self.number = number
        machinePath = machine.id
        libraryRoot = machine.libraryRoot
        machineName = machine.name
        machineUDID = machine.udid
        directoryIdentity = machine.directoryIdentity
        self.region = region
        self.notes = notes
    }

    var device: VPhoneFlywheelDevice {
        VPhoneFlywheelDevice(
            id: id, number: number,
            machine: .init(libraryRoot: libraryRoot, name: machineName, udid: machineUDID, directoryIdentity: directoryIdentity),
            region: region, notes: notes
        )
    }
}
