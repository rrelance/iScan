import XCTest
@testable import ScanKit

final class SmokeTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(ScanKit.schemaVersion, 1)
    }
}
