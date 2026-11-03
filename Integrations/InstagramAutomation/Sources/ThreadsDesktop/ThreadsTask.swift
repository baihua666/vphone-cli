#if VPHONE_CUSTOM_THREADS_DESKTOP
import Foundation

public struct ThreadsAccount: Codable, Identifiable, Equatable, Sendable {
    public var id: String { username }
    public var username: String
    public var machinePath: String
    public init(username: String, machinePath: String) {
        self.username = username; self.machinePath = machinePath
    }
}

/// Immutable request shared by the GUI and the existing automation executable.
public struct ThreadsTaskRequest: Codable, Equatable, Sendable {
    public let account: String
    public let socket: String
    public let marker: String
    public let caption: String
    public let freshLogin: Bool
    public let testProfile: Bool
    public let hasImage: Bool?
    public let sourceImageName: String?
    public var imageName: String { sourceImageName ?? "fixture.png" }
    public var includesImage: Bool { hasImage ?? true }
    public init(account: String, socket: String, marker: String, caption: String,
                freshLogin: Bool = false, testProfile: Bool = false, hasImage: Bool? = nil, sourceImageName: String? = nil) {
        self.account = account; self.socket = socket; self.marker = marker
        self.caption = caption; self.freshLogin = freshLogin; self.testProfile = testProfile
        self.hasImage = hasImage
        self.sourceImageName = sourceImageName
    }
    public var publishedCaption: String { caption }
    public func validate() throws {
        guard account.range(of: "^[A-Za-z0-9_.]{1,30}$", options: .regularExpression) != nil,
              marker.range(of: "^VPHONE-[A-F0-9]{8}$", options: .regularExpression) != nil,
              socket.hasPrefix("/"), socket.hasSuffix("/vphone.sock"),
              includesImage || !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              imageName.range(of: "^[A-Za-z0-9_-]+\\.[A-Za-z0-9]{1,10}$", options: .regularExpression) != nil,
              publishedCaption.count <= 500 else { throw ThreadsDesktopError("账号、实例或文案无效（最多 500 字）") }
    }
}

public struct ThreadsTaskRecord: Codable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let request: ThreadsTaskRequest
    public var status: String
    public var detail: String
}

public struct ThreadsDesktopError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

#endif
