import Foundation

// Test transport only: compile the production unlock implementation below.
enum GuestAPIError: Error { case invalidRequest(String), operationFailed(String) }
enum ScreenFixture {
    nonisolated(unsafe) static var began = Date()
    nonisolated(unsafe) static var lockDelay: TimeInterval = 0
    nonisolated(unsafe) static var dismissed = false
    nonisolated(unsafe) static var homePresses = 0
}
func lockState() -> [String: Any] {
    ["locked": !ScreenFixture.dismissed && Date().timeIntervalSince(ScreenFixture.began) >= ScreenFixture.lockDelay,
     "screen_off": false]
}
func collectDeviceSnapshot() throws -> [String: Any] { ["lock": ["passcode_enabled": false]] }
func vp_screen_undim() -> Bool { true }
func pressButton(_ name: String) throws -> Bool {
    precondition(name == "home")
    ScreenFixture.homePresses += 1
    ScreenFixture.dismissed = true
    return true
}
func hidPress(page: Int, usage: Int) throws -> Bool { true }
func typeText(_ text: String, delayMS: Int) throws -> Bool { true }
func pressKey(_ key: String) throws -> Bool { true }

@main
struct ScreenUnlockTests {
    static func main() throws {
        for delay in [0.0, 0.35] {
            ScreenFixture.began = Date()
            ScreenFixture.lockDelay = delay
            ScreenFixture.dismissed = false
            ScreenFixture.homePresses = 0
            GuestScreenUnlock.springBoardDidRestart()
            let result = try GuestScreenUnlock.unlock(passcode: nil, timeout: 2)
            precondition(result["was_locked"] as? Bool == true)
            precondition(result["locked"] as? Bool == false)
            precondition(ScreenFixture.homePresses == 1)
            precondition(Date().timeIntervalSince(ScreenFixture.began) >= delay)
        }
        print("Screen unlock tests passed: immediate and delayed post-respring Lock Screen")
    }
}
