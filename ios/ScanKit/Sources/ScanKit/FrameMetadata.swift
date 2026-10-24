import Foundation
import simd

/// Per-photo sidecar (`frames/NNNN.json`). Matrices are flattened column-major.
public struct FrameMetadata: Codable, Equatable {
    public var index: Int
    public var timestamp: Double
    public var imageResolution: [Int]
    public var intrinsics: [Float]
    public var cameraTransform: [Float]
    /// Depth comes from the nearest regular ARFrame, so it carries its own resolution, intrinsics and pose.
    public var depthResolution: [Int]?
    public var depthIntrinsics: [Float]?
    public var depthTransform: [Float]?
    public var trackingState: String

    public init(index: Int, timestamp: Double, imageResolution: [Int], intrinsics: [Float], cameraTransform: [Float],
                depthResolution: [Int]?, depthIntrinsics: [Float]?, depthTransform: [Float]?, trackingState: String) {
        self.index = index
        self.timestamp = timestamp
        self.imageResolution = imageResolution
        self.intrinsics = intrinsics
        self.cameraTransform = cameraTransform
        self.depthResolution = depthResolution
        self.depthIntrinsics = depthIntrinsics
        self.depthTransform = depthTransform
        self.trackingState = trackingState
    }
}

/// Rescales a pinhole intrinsics matrix from one image resolution to another.
public func scaleIntrinsics(_ k: simd_float3x3, from: SIMD2<Float>, to: SIMD2<Float>) -> simd_float3x3 {
    let sx = to.x / from.x
    let sy = to.y / from.y
    var out = k
    out[0][0] = k[0][0] * sx
    out[1][1] = k[1][1] * sy
    out[2][0] = k[2][0] * sx
    out[2][1] = k[2][1] * sy
    return out
}

public func flatten(_ m: simd_float3x3) -> [Float] {
    [m.columns.0, m.columns.1, m.columns.2].flatMap { [$0.x, $0.y, $0.z] }
}

public func flatten(_ m: simd_float4x4) -> [Float] {
    [m.columns.0, m.columns.1, m.columns.2, m.columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] }
}
