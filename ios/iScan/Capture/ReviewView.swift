import ScanKit
import SwiftUI

/// Summary after a scan, with upload and done.
struct ReviewView: View {
    let manifest: Manifest
    let dir: URL
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Scan \(manifest.scanId)") {
                    LabeledContent("Photos", value: "\(manifest.detailPass.frameCount)")
                    LabeledContent("Mesh faces", value: "\(manifest.detailPass.meshFaceCount)")
                    LabeledContent("Room pass", value: manifest.roomPass.map { "\($0.surfaceCount) surfaces, \($0.objectCount) objects" } ?? "Skipped")
                    LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: Self.size(of: dir), countStyle: .file))
                }
                Section {
                    Button("Upload to PC") {}
                        .disabled(true)
                }
            }
            .navigationTitle("Scan saved")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) }
            }
        }
    }

    static func size(of dir: URL) -> Int64 {
        let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        while let url = files?.nextObject() as? URL {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
