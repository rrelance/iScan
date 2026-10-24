import ARKit
import CoreImage
import ScanKit

/// Converts ARKit buffers into the plain arrays and files ScanKit writes.
enum FrameExport {
    private static let context = CIContext()

    static func jpeg(from buffer: CVPixelBuffer, quality: CGFloat = 0.9) -> Data? {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let options = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality]
        return context.jpegRepresentation(of: CIImage(cvPixelBuffer: buffer), colorSpace: srgb, options: options)
    }

    /// Depth in millimeters and per-pixel confidence (ARConfidenceLevel raw values), row-major.
    static func depthArrays(_ d: ARDepthData) -> (mm: [UInt16], conf: [UInt8], width: Int, height: Int) {
        let map = d.depthMap
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        var meters = [Float](repeating: 0, count: width * height)
        CVPixelBufferLockBaseAddress(map, .readOnly)
        if let base = CVPixelBufferGetBaseAddress(map) {
            let rowBytes = CVPixelBufferGetBytesPerRow(map)
            for y in 0..<height {
                let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
                for x in 0..<width { meters[y * width + x] = row[x] }
            }
        }
        CVPixelBufferUnlockBaseAddress(map, .readOnly)

        var conf = [UInt8](repeating: 0, count: width * height)
        if let c = d.confidenceMap {
            CVPixelBufferLockBaseAddress(c, .readOnly)
            if let base = CVPixelBufferGetBaseAddress(c) {
                let rowBytes = CVPixelBufferGetBytesPerRow(c)
                for y in 0..<min(height, CVPixelBufferGetHeight(c)) {
                    let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
                    for x in 0..<min(width, CVPixelBufferGetWidth(c)) { conf[y * width + x] = row[x] }
                }
            }
            CVPixelBufferUnlockBaseAddress(c, .readOnly)
        }
        return (DepthPNG.millimeters(fromMeters: meters), conf, width, height)
    }

    /// The anchor's mesh with vertices moved into world space.
    static func meshChunk(_ anchor: ARMeshAnchor) -> MeshChunk {
        let g = anchor.geometry
        let v = g.vertices
        let vbase = v.buffer.contents().advanced(by: v.offset)
        let vertices: [SIMD3<Float>] = (0..<v.count).map { i in
            let p = vbase.advanced(by: i * v.stride).assumingMemoryBound(to: Float.self)
            let world = anchor.transform * SIMD4<Float>(p[0], p[1], p[2], 1)
            return SIMD3(world.x, world.y, world.z)
        }

        let f = g.faces
        let fbase = f.buffer.contents()
        let faces: [SIMD3<UInt32>] = (0..<f.count).map { i in
            let start = fbase.advanced(by: i * f.indexCountPerPrimitive * f.bytesPerIndex)
            func index(_ k: Int) -> UInt32 {
                f.bytesPerIndex == 2
                    ? UInt32(start.advanced(by: k * 2).assumingMemoryBound(to: UInt16.self).pointee)
                    : start.advanced(by: k * 4).assumingMemoryBound(to: UInt32.self).pointee
            }
            return SIMD3(index(0), index(1), index(2))
        }

        var classification = [UInt8](repeating: 0, count: f.count)
        if let c = g.classification {
            let cbase = c.buffer.contents().advanced(by: c.offset)
            for i in 0..<min(f.count, c.count) {
                classification[i] = cbase.advanced(by: i * c.stride).assumingMemoryBound(to: UInt8.self).pointee
            }
        }
        return MeshChunk(vertices: vertices, faces: faces, classification: classification)
    }
}
