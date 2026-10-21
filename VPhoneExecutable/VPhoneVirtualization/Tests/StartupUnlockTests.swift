import Foundation

// Only the transport is replaced; the runner compiles the real production extension.
@MainActor
final class VPhoneGuestControl {
    enum ControlError: Error { case guestError(String) }
    var replies: [Result<[String: Any], ControlError>]
    var methods: [String] = []

    init(_ replies: [Result<[String: Any], ControlError>]) { self.replies = replies }

    func call(_ method: String, params _: [String: Any] = [:]) async throws -> [String: Any] {
        methods.append(method)
        guard !replies.isEmpty else { throw ControlError.guestError("Unexpected request: \(method)") }
        return try replies.removeFirst().get()
    }

    func sendRequest(_: [String: Any]) async throws -> ([String: Any], Data?) {
        throw ControlError.guestError("Unexpected sendRequest")
    }
}

@main
struct StartupUnlockTests {
    enum Failure: Error { case expectation(String) }

    @MainActor
    static func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure.expectation(message) }
    }

    @MainActor
    static func main() async {
        do {
            for message in ["the Lock Screen did not dismiss in time", "the display did not turn on within 60 s"] {
                let control = VPhoneGuestControl([.failure(.guestError(message)), .success(["was_locked": true])])
                await control.unlockAtStartup()
                try check(control.methods == ["screen.unlock", "screen.unlock"], "Startup timeout must be retried: \(message)")
                try check(control.replies.isEmpty, "The successful retry must be consumed")
            }

            for message in ["the device has a passcode; pass it as passcode", "Connection reset by peer"] {
                let control = VPhoneGuestControl([.failure(.guestError(message)), .success(["was_locked": true])])
                await control.unlockAtStartup()
                try check(control.methods == ["screen.unlock"], "Non-startup errors must not be retried: \(message)")
            }

            let lateLock = VPhoneGuestControl([
                .success(["was_locked": false]), .success(["locked": true]), .success(["was_locked": true]),
            ])
            await lateLock.unlockAtStartup()
            try check(lateLock.methods == ["screen.unlock", "device.screen", "screen.unlock"], "A late Lock Screen must still be dismissed")
            print("PASS: timeout recovery, terminal failures and late Lock Screen")
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }
}
