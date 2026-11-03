import XCTest
@testable import InstagramAutomation
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION
final class CredentialsTests: XCTestCase {
    func testLocalPasswordPreservesSpacesAndAcceptsOneLineEnding() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertNil(try Credentials.filePassword("test", directory: directory))
        let file = directory.appendingPathComponent("test.password")
        try " example password \r\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(try Credentials.filePassword("test", directory: directory), " example password ")
        for invalid in ["", "\n", "first\nsecond"] {
            try invalid.write(to: file, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try Credentials.filePassword("test", directory: directory))
        }
        XCTAssertThrowsError(try Credentials.filePassword("../other", directory: directory))
    }
}
#endif
