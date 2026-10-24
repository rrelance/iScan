import Foundation
import simd

/// Decides when the detail pass should take the next high-res photo: only with normal tracking,
/// one capture in flight at a time, and only after enough movement or rotation.
public struct CaptureThrottle {
    public let minTranslation: Float
    public let minRotationDegrees: Float
    public let minInterval: TimeInterval

    private var lastPose: simd_float4x4?
    private var lastTime: TimeInterval = -.infinity
    private var inFlight = false

    public init(minTranslation: Float = 0.5, minRotationDegrees: Float = 20, minInterval: TimeInterval = 0.7) {
        self.minTranslation = minTranslation
        self.minRotationDegrees = minRotationDegrees
        self.minInterval = minInterval
    }

    /// Returns true when a capture should start now, and marks it in flight.
    public mutating func shouldCapture(transform: simd_float4x4, time: TimeInterval, trackingNormal: Bool) -> Bool {
        guard trackingNormal, !inFlight, time - lastTime >= minInterval else { return false }
        if let last = lastPose {
            let moved = simd_distance(last.columns.3.xyz, transform.columns.3.xyz)
            guard moved >= minTranslation || rotationDegrees(from: last, to: transform) >= minRotationDegrees else {
                return false
            }
        }
        lastPose = transform
        lastTime = time
        inFlight = true
        return true
    }

    /// Manual shutter: ignores movement, tracking and interval, but never overlaps an in-flight capture.
    public mutating func forceCapture(time: TimeInterval) -> Bool {
        guard !inFlight else { return false }
        lastTime = time
        inFlight = true
        return true
    }

    public mutating func captureFinished() {
        inFlight = false
    }

    private func rotationDegrees(from a: simd_float4x4, to b: simd_float4x4) -> Float {
        let ra = simd_float3x3(columns: (a.columns.0.xyz, a.columns.1.xyz, a.columns.2.xyz))
        let rb = simd_float3x3(columns: (b.columns.0.xyz, b.columns.1.xyz, b.columns.2.xyz))
        let rel = ra.transpose * rb
        let trace = rel[0][0] + rel[1][1] + rel[2][2]
        return acos(min(1, max(-1, (trace - 1) / 2))) * 180 / .pi
    }
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
