import XCTest
import simd
@testable import ScanKit

final class FrameMetadataTests: XCTestCase {
    func testScaleIntrinsicsToDepthResolution() {
        let k = simd_float3x3(columns: (
            SIMD3<Float>(1500, 0, 0),
            SIMD3<Float>(0, 1500, 0),
            SIMD3<Float>(960, 720, 1)
        ))
        let s = scaleIntrinsics(k, from: SIMD2<Float>(1920, 1440), to: SIMD2<Float>(256, 192))
        XCTAssertEqual(s[0][0], 200, accuracy: 1e-3)
        XCTAssertEqual(s[1][1], 200, accuracy: 1e-3)
        XCTAssertEqual(s[2][0], 128, accuracy: 1e-3)
        XCTAssertEqual(s[2][1], 96, accuracy: 1e-3)
        XCTAssertEqual(s[2][2], 1, accuracy: 1e-6)
    }

    func testFlattenIsColumnMajor() {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4<Float>(1, 2, 3, 1)
        let f = flatten(m)
        XCTAssertEqual(f.count, 16)
        XCTAssertEqual(Array(f[12...14]), [1, 2, 3])
        XCTAssertEqual(flatten(matrix_identity_float3x3).count, 9)
    }
}
