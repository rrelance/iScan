import XCTest
@testable import ScanKit

final class BundleLayoutTests: XCTestCase {
    func testScanIdFormatsLocalTime() {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 24; c.hour = 14; c.minute = 5; c.second = 9
        c.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar(identifier: .gregorian).date(from: c)!
        XCTAssertEqual(BundleLayout.scanId(for: date, timeZone: TimeZone(identifier: "UTC")!), "20261024-140509")
    }

    func testScanIdValidation() {
        XCTAssertTrue(BundleLayout.isValidScanId("20261024-140509"))
        XCTAssertFalse(BundleLayout.isValidScanId("2026-10-24"))
        XCTAssertFalse(BundleLayout.isValidScanId("../x"))
        XCTAssertFalse(BundleLayout.isValidScanId(""))
    }

    func testFramePathsAreFourDigitOneBased() {
        let p = BundleLayout.framePaths(index: 7)
        XCTAssertEqual(p.jpg, "frames/0007.jpg")
        XCTAssertEqual(p.json, "frames/0007.json")
        XCTAssertEqual(p.depth, "frames/0007_depth.png")
        XCTAssertEqual(p.conf, "frames/0007_conf.png")
    }
}
