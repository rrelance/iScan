import Foundation

/// Closes out a scan bundle: writes the mesh, fills in the counts, and writes `manifest.json` last.
public enum BundleFinalizer {
    public static func finalize(dir: URL, manifest: Manifest, meshChunks: [MeshChunk]) throws -> Manifest {
        let counts = try PLYWriter.write(meshChunks, to: dir.appendingPathComponent(BundleLayout.mesh))
        let frames = (try? FileManager.default.contentsOfDirectory(
            atPath: dir.appendingPathComponent(BundleLayout.framesDir).path)) ?? []

        var final = manifest
        final.detailPass = Manifest.DetailPassInfo(frameCount: frames.filter { $0.hasSuffix(".jpg") }.count,
                                                   meshFaceCount: counts.faces)
        try Manifest.encoder().encode(final).write(to: dir.appendingPathComponent(BundleLayout.manifest),
                                                   options: .atomic)
        return final
    }
}
