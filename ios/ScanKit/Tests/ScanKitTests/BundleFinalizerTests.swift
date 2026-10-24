import XCTest
import simd
@testable import ScanKit

final class BundleFinalizerTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func draft() -> Manifest {
        Manifest(scanId: "20261024-140509", createdAt: Date(timeIntervalSince1970: 0), device: "iPhone13,4",
                 systemVersion: "16.4.1", sessionReused: false, roomPass: nil,
                 detailPass: Manifest.DetailPassInfo(frameCount: 0, meshFaceCount: 0))
    }

    func testCountsFramesAndFacesAndWritesFiles() throws {
        let frames = dir.appendingPathComponent("frames")
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        for name in ["0001.jpg", "0002.jpg", "0001.json", "0001_depth.png"] {
            try Data([1]).write(to: frames.appendingPathComponent(name))
        }
        let chunk = MeshChunk(vertices: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
                              faces: [SIMD3(0, 1, 2)], classification: [1])

        let result = try BundleFinalizer.finalize(dir: dir, manifest: draft(), meshChunks: [chunk])

        XCTAssertEqual(result.detailPass, Manifest.DetailPassInfo(frameCount: 2, meshFaceCount: 1))
        let written = try Manifest.decoder().decode(Manifest.self,
                                                    from: Data(contentsOf: dir.appendingPathComponent("manifest.json")))
        XCTAssertEqual(written, result)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("mesh.ply").path))
    }

    func testZeroFramesAndNoMeshStillProducesAValidBundle() throws {
        let result = try BundleFinalizer.finalize(dir: dir, manifest: draft(), meshChunks: [])

        XCTAssertEqual(result.detailPass, Manifest.DetailPassInfo(frameCount: 0, meshFaceCount: 0))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("manifest.json").path))
        let ply = try Data(contentsOf: dir.appendingPathComponent("mesh.ply"))
        XCTAssertEqual(ply.count, PLYWriter.header(vertexCount: 0, faceCount: 0).utf8.count)
    }
}
