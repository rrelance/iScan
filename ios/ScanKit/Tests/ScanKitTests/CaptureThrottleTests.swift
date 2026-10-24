import XCTest
import simd
@testable import ScanKit

final class CaptureThrottleTests: XCTestCase {
    private func pose(x: Float = 0, yawDegrees: Float = 0) -> simd_float4x4 {
        var m = simd_float4x4(simd_quatf(angle: yawDegrees * .pi / 180, axis: SIMD3<Float>(0, 1, 0)))
        m.columns.3 = SIMD4<Float>(x, 0, 0, 1)
        return m
    }

    func testFirstNormalPoseCaptures() {
        var t = CaptureThrottle()
        XCTAssertTrue(t.shouldCapture(transform: pose(), time: 0, trackingNormal: true))
    }

    func testNoSecondCaptureWhileOneIsInFlight() {
        var t = CaptureThrottle()
        _ = t.shouldCapture(transform: pose(), time: 0, trackingNormal: true)
        XCTAssertFalse(t.shouldCapture(transform: pose(x: 2), time: 5, trackingNormal: true))
    }

    func testTranslationThreshold() {
        var t = CaptureThrottle()
        _ = t.shouldCapture(transform: pose(), time: 0, trackingNormal: true)
        t.captureFinished()
        XCTAssertFalse(t.shouldCapture(transform: pose(x: 0.3), time: 1, trackingNormal: true))
        XCTAssertTrue(t.shouldCapture(transform: pose(x: 0.6), time: 1, trackingNormal: true))
    }

    func testRotationThreshold() {
        var t = CaptureThrottle()
        _ = t.shouldCapture(transform: pose(), time: 0, trackingNormal: true)
        t.captureFinished()
        XCTAssertFalse(t.shouldCapture(transform: pose(yawDegrees: 10), time: 1, trackingNormal: true))
        XCTAssertTrue(t.shouldCapture(transform: pose(yawDegrees: 25), time: 1, trackingNormal: true))
    }

    func testMinimumInterval() {
        var t = CaptureThrottle()
        _ = t.shouldCapture(transform: pose(), time: 0, trackingNormal: true)
        t.captureFinished()
        XCTAssertFalse(t.shouldCapture(transform: pose(x: 0.6), time: 0.2, trackingNormal: true))
    }

    func testLimitedTrackingNeverCaptures() {
        var t = CaptureThrottle()
        XCTAssertFalse(t.shouldCapture(transform: pose(), time: 0, trackingNormal: false))
        XCTAssertTrue(t.shouldCapture(transform: pose(), time: 1, trackingNormal: true))
        t.captureFinished()
        XCTAssertFalse(t.shouldCapture(transform: pose(x: 5), time: 10, trackingNormal: false))
    }
}
