import XCTest
@testable import ScanKit

final class ManifestTests: XCTestCase {
    private func sample() -> Manifest {
        Manifest(
            schemaVersion: 1,
            scanId: "20261024-140509",
            createdAt: Date(timeIntervalSince1970: 1_792_850_709),
            device: "iPhone13,4",
            systemVersion: "16.4.1",
            units: "meters",
            sessionReused: false,
            roomPass: Manifest.RoomPassInfo(surfaceCount: 9, objectCount: 3),
            detailPass: Manifest.DetailPassInfo(frameCount: 120, meshFaceCount: 50_000)
        )
    }

    func testRoundTrip() throws {
        let data = try Manifest.encoder().encode(sample())
        XCTAssertEqual(try Manifest.decoder().decode(Manifest.self, from: data), sample())
    }

    func testEncodedJSONUsesMetersAndISO8601() throws {
        let json = String(decoding: try Manifest.encoder().encode(sample()), as: UTF8.self)
        XCTAssertTrue(json.contains("\"units\" : \"meters\""), json)
        XCTAssertTrue(json.contains("\"createdAt\" : \"2026-10-24T"), json)
    }

    func testSkippedRoomPassRoundTrips() throws {
        var m = sample()
        m.roomPass = nil
        let data = try Manifest.encoder().encode(m)
        XCTAssertNil(try Manifest.decoder().decode(Manifest.self, from: data).roomPass)
    }
}
