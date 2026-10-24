import XCTest
import simd
@testable import ScanKit

final class PLYWriterTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ply")
    }

    private func uint32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(littleEndian: data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
    }

    func testHeaderIsExact() {
        XCTAssertEqual(PLYWriter.header(vertexCount: 7, faceCount: 3), """
        ply
        format binary_little_endian 1.0
        element vertex 7
        property float x
        property float y
        property float z
        element face 3
        property list uchar uint vertex_indices
        property uchar classification
        end_header

        """)
    }

    func testMergesChunksAndOffsetsFaceIndices() throws {
        let a = MeshChunk(vertices: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
                          faces: [SIMD3(0, 1, 2)], classification: [1])
        let b = MeshChunk(vertices: [SIMD3(0, 0, 1), SIMD3(1, 0, 1), SIMD3(1, 1, 1), SIMD3(0, 1, 1)],
                          faces: [SIMD3(0, 1, 2), SIMD3(0, 2, 3)], classification: [2, 2])
        let url = tempURL()
        let counts = try PLYWriter.write([a, b], to: url)
        XCTAssertEqual(counts.vertices, 7)
        XCTAssertEqual(counts.faces, 3)

        let data = try Data(contentsOf: url)
        let headerLength = PLYWriter.header(vertexCount: 7, faceCount: 3).utf8.count
        XCTAssertEqual(data.count, headerLength + 7 * 12 + 3 * (1 + 12 + 1))

        let secondChunkFace = headerLength + 7 * 12 + 14
        XCTAssertEqual(data[secondChunkFace], 3)
        XCTAssertEqual(uint32(data, at: secondChunkFace + 1), 3)
        XCTAssertEqual(uint32(data, at: secondChunkFace + 5), 4)
        XCTAssertEqual(uint32(data, at: secondChunkFace + 9), 5)
        XCTAssertEqual(data[secondChunkFace + 13], 2)
    }
}
