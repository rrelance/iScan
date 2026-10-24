import XCTest
@testable import ScanKit

final class UploadPlanTests: XCTestCase {
    private let local = [
        UploadFile(path: "frames/0001.jpg", size: 100),
        UploadFile(path: "frames/0001.json", size: 10),
        UploadFile(path: "manifest.json", size: 50),
        UploadFile(path: "mesh.ply", size: 400),
        UploadFile(path: "walls.json", size: 30),
    ]

    func testPendingSkipsMatchingFilesAndUploadsManifestLast() {
        let remote = [UploadFile(path: "frames/0001.jpg", size: 100), UploadFile(path: "mesh.ply", size: 3)]
        let pending = UploadPlan.pending(local: local, remote: remote)
        XCTAssertEqual(pending.map(\.path), ["frames/0001.json", "mesh.ply", "walls.json", "manifest.json"])
    }

    func testNothingPendingWhenRemoteMatches() {
        XCTAssertEqual(UploadPlan.pending(local: local, remote: local.reversed()), [])
    }

    func testLocalFilesAreRecursiveSortedAndSkipDotfiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("frames"), withIntermediateDirectories: true)
        try Data(count: 3).write(to: dir.appendingPathComponent("mesh.ply"))
        try Data(count: 5).write(to: dir.appendingPathComponent("frames/0001.jpg"))
        try Data(count: 1).write(to: dir.appendingPathComponent(".DS_Store"))
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertEqual(try UploadPlan.localFiles(in: dir),
                       [UploadFile(path: "frames/0001.jpg", size: 5), UploadFile(path: "mesh.ply", size: 3)])
    }
}
