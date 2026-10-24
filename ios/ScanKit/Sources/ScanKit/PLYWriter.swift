import Foundation
import simd

/// One ARMeshAnchor's geometry, already transformed to world space.
public struct MeshChunk {
    public var vertices: [SIMD3<Float>]
    public var faces: [SIMD3<UInt32>]
    /// ARMeshClassification raw value per face (0 when unavailable).
    public var classification: [UInt8]

    public init(vertices: [SIMD3<Float>], faces: [SIMD3<UInt32>], classification: [UInt8]) {
        self.vertices = vertices
        self.faces = faces
        self.classification = classification
    }
}

/// Writes mesh chunks as one binary little-endian PLY with a per-face classification.
public enum PLYWriter {
    public static func header(vertexCount: Int, faceCount: Int) -> String {
        """
        ply
        format binary_little_endian 1.0
        element vertex \(vertexCount)
        property float x
        property float y
        property float z
        element face \(faceCount)
        property list uchar uint vertex_indices
        property uchar classification
        end_header

        """
    }

    @discardableResult
    public static func write(_ chunks: [MeshChunk], to url: URL) throws -> (vertices: Int, faces: Int) {
        let vertexCount = chunks.reduce(0) { $0 + $1.vertices.count }
        let faceCount = chunks.reduce(0) { $0 + $1.faces.count }
        var data = Data(header(vertexCount: vertexCount, faceCount: faceCount).utf8)
        data.reserveCapacity(data.count + vertexCount * 12 + faceCount * 14)

        for chunk in chunks {
            for v in chunk.vertices {
                append(&data, v.x.bitPattern)
                append(&data, v.y.bitPattern)
                append(&data, v.z.bitPattern)
            }
        }
        var offset: UInt32 = 0
        for chunk in chunks {
            for (i, f) in chunk.faces.enumerated() {
                data.append(3)
                append(&data, f.x + offset)
                append(&data, f.y + offset)
                append(&data, f.z + offset)
                data.append(i < chunk.classification.count ? chunk.classification[i] : 0)
            }
            offset += UInt32(chunk.vertices.count)
        }
        try data.write(to: url, options: .atomic)
        return (vertexCount, faceCount)
    }

    private static func append(_ data: inout Data, _ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}
