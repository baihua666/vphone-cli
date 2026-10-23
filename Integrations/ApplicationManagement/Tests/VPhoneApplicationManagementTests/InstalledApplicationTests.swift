import XCTest
@testable import VPhoneApplicationManagement

final class InstalledApplicationTests: XCTestCase {
    func testVersionAndBuildComparison() {
        let guest = VPhoneInstalledApplication(version: "47.4.0", build: "474032")
        XCTAssertEqual(guest.compare(localVersion: "47.4.0", localBuild: "474032"), .current)
        XCTAssertEqual(guest.compare(localVersion: "47.4", localBuild: "474032"), .current)
        XCTAssertEqual(guest.compare(localVersion: "47.4.0", localBuild: "474033"), .upgrade)
        XCTAssertEqual(guest.compare(localVersion: "47.4.0", localBuild: "474031"), .guestNewer)
        XCTAssertEqual(guest.compare(localVersion: "47.10.0", localBuild: "1"), .upgrade)
        XCTAssertEqual(guest.compare(localVersion: "47.3.9", localBuild: "999999"), .guestNewer)
        XCTAssertEqual(guest.compare(localVersion: "未知", localBuild: "474032"), .unknown)
        XCTAssertEqual(guest.compare(localVersion: "47.4.0", localBuild: nil), .unknown)
        XCTAssertEqual(guest.compare(localVersion: "47.4.0-beta", localBuild: "1"), .unknown)
        XCTAssertEqual(VPhoneInstalledApplication.compareNumbers("1.09", "1.9.0"), .orderedSame)
        XCTAssertEqual(VPhoneInstalledApplication.compareNumbers("999999999999999999999999", "2"), .orderedDescending)
    }

    func testGuestSnapshotUsesBundleIDAndPreservesMissingVersion() throws {
        let apps = try VPhoneInstalledApplication.parse(["apps": [
            ["bundle_id": "com.zhiliaoapp.musically", "name": "TikTok", "version": "47.4.0", "build": "474032"],
            ["bundle_id": "com.example.other", "name": "TikTok"]
        ]])
        XCTAssertEqual(apps.count, 2)
        XCTAssertEqual(apps["com.zhiliaoapp.musically"]?.compare(localVersion: "47.4.0", localBuild: "474032"), .current)
        XCTAssertEqual(apps["com.example.other"]?.compare(localVersion: "47.4.0", localBuild: "474032"), .unknown)
        XCTAssertTrue(try VPhoneInstalledApplication.parse(["apps": []]).isEmpty)
        XCTAssertThrowsError(try VPhoneInstalledApplication.parse([:]))
        XCTAssertThrowsError(try VPhoneInstalledApplication.parse(["apps": [["name": "missing identity"]]]))
    }
}
