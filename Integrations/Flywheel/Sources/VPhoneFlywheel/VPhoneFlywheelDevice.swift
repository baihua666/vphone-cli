import Foundation

/// A platform locator. Directory identity distinguishes renames from same-UDID clones.
public struct VPhoneFlywheelMachineReference: Hashable, Sendable, Identifiable {
    public let libraryRoot: String
    public let name: String
    public let udid: String?
    public let directoryIdentity: String?

    public init(libraryRoot: String, name: String, udid: String?, directoryIdentity: String? = nil) {
        self.libraryRoot = libraryRoot
        self.name = name
        self.udid = udid
        self.directoryIdentity = directoryIdentity
    }

    public var id: String {
        URL(fileURLWithPath: libraryRoot, isDirectory: true).appendingPathComponent(name).path
    }

    public func matches(_ current: Self) -> Bool {
        libraryRoot == current.libraryRoot && name == current.name && udid == current.udid
            && directoryIdentity == current.directoryIdentity
    }

    /// Local filesystem metadata only; nothing is written into the platform directory.
    public static func directoryIdentity(at url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeDirectory,
              let volume = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber,
              let created = attributes[.creationDate] as? Date else { return nil }
        return "\(volume):\(inode):\(created.timeIntervalSince1970)"
    }
}

public struct VPhoneFlywheelDevice: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let number: String
    public let machine: VPhoneFlywheelMachineReference
    public let region: String
    public let notes: String

    public func matches(search: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || [number, machine.name, machine.libraryRoot, region, notes]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

public enum VPhoneFlywheelValidation {
    public static let regionCodes = Set(Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 })

    public static func number(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw VPhoneFlywheelError("设备编号只能包含数字 0–9。")
        }
        let digits = value.drop(while: { $0 == "0" })
        return digits.isEmpty ? "0" : String(digits)
    }

    public static func region(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard value.isEmpty || regionCodes.contains(value) else {
            throw VPhoneFlywheelError("请选择有效的国家或地区。")
        }
        return value
    }
}

public struct VPhoneFlywheelError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
