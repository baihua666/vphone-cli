import Foundation
import Observation

public struct VPhoneFlywheelURLParameter: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var isEnabled: Bool
    public var name: String
    public var value: String

    public init(id: UUID = UUID(), isEnabled: Bool = true, name: String = "", value: String = "") {
        self.id = id
        self.isEnabled = isEnabled
        self.name = name
        self.value = value
    }

    var key: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func validate(_ parameters: [Self]) throws {
        for (index, parameter) in parameters.enumerated() {
            guard parameter.key != "ip" else {
                throw VPhoneFlywheelError("第 \(index + 1) 行：ip 为自动参数，请使用上方的 ip 勾选项。")
            }
            if parameter.isEnabled, parameter.key.isEmpty, !parameter.value.isEmpty {
                throw VPhoneFlywheelError("第 \(index + 1) 行：请填写参数名，或取消勾选此行。")
            }
        }
    }
}

/// Local preferences only; independent of the business device database and VM manifests.
@Observable @MainActor
public final class VPhoneFlywheelURLParameterStore {
    public static let shared = VPhoneFlywheelURLParameterStore()
    public static let preferenceKey = "flywheel.businessWebParameters"
    @ObservationIgnored private let defaults: UserDefaults
    public private(set) var error: String?
    public var parameters: [VPhoneFlywheelURLParameter] {
        didSet {
            do {
                defaults.set(try JSONEncoder().encode(parameters), forKey: Self.preferenceKey)
                error = nil
            } catch { self.error = "URL 参数保存失败：" + error.localizedDescription }
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        do {
            if let stored = defaults.object(forKey: Self.preferenceKey) {
                guard let data = stored as? Data else {
                    throw VPhoneFlywheelError("保存的参数格式无效。")
                }
                parameters = try JSONDecoder().decode([VPhoneFlywheelURLParameter].self, from: data)
                guard Set(parameters.map(\.id)).count == parameters.count else {
                    throw VPhoneFlywheelError("保存的参数行标识重复。")
                }
            } else { parameters = [] }
        } catch {
            parameters = []
            self.error = "URL 参数读取失败，原配置已保留：" + error.localizedDescription
        }
    }
}
