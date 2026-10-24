import XCTest
@testable import ScanKit

final class RoomSummaryTests: XCTestCase {
    func testRoundTrip() throws {
        let wall = SurfaceRecord(kind: "wall", category: "wall",
                                 transform: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 2, 1.2, 3, 1],
                                 dimensions: [4.0, 2.4, 0], confidence: "high")
        let summary = RoomSummary(schemaVersion: 1, walls: [wall], doors: [], windows: [], openings: [], objects: [])
        let decoded = try JSONDecoder().decode(RoomSummary.self, from: JSONEncoder().encode(summary))
        XCTAssertEqual(decoded, summary)
        XCTAssertEqual(decoded.walls[0].dimensions.count, 3)
        XCTAssertEqual(decoded.walls[0].transform.count, 16)
    }
}
