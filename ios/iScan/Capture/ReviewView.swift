import ScanKit
import SwiftUI
import UIKit

/// Shown right after a scan finishes.
struct ReviewView: View {
    let manifest: Manifest
    let dir: URL
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScanSummaryList(scanId: manifest.scanId, dir: dir, manifest: manifest)
                .navigationTitle("Scan saved")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) }
                }
        }
    }
}

/// Scan stats plus upload/share; used after capture and from the scan list.
struct ScanSummaryList: View {
    let scanId: String
    let dir: URL
    let manifest: Manifest?

    var body: some View {
        List {
            Section("Scan \(scanId)") {
                if let manifest {
                    LabeledContent("Photos", value: "\(manifest.detailPass.frameCount)")
                    LabeledContent("Mesh faces", value: "\(manifest.detailPass.meshFaceCount)")
                    LabeledContent("Room pass", value: manifest.roomPass.map {
                        "\($0.surfaceCount) surfaces, \($0.objectCount) objects"
                    } ?? "Skipped")
                } else {
                    Text("This scan didn't finish, so it has no manifest.").foregroundStyle(.orange)
                }
                LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: Self.size(of: dir), countStyle: .file))
            }
            UploadPanel(dir: dir, scanId: scanId)
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

private struct UploadPanel: View {
    let dir: URL
    let scanId: String

    @AppStorage("serverURL") private var serverURL = ""
    @StateObject private var uploader = Uploader()
    @State private var sharing = false

    private var base: URL? {
        serverURL.isEmpty ? nil : URL(string: serverURL)
    }

    var body: some View {
        Section {
            Button {
                if let base { Task { await uploader.upload(scanDir: dir, scanId: scanId, base: base) } }
            } label: {
                Label(uploader.state == .uploading ? "Uploading…" : "Upload to PC", systemImage: "arrow.up.circle")
            }
            .disabled(base == nil || uploader.state == .uploading)

            switch uploader.state {
            case .idle:
                if base == nil { Text("Set your PC's address in Settings first.").foregroundStyle(.secondary) }
            case .uploading:
                ProgressView(value: uploader.progress)
            case .done:
                Label("Uploaded to \(base?.host ?? "PC")", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed(let message):
                Text(message).foregroundStyle(.red)
                Button("Retry") {
                    if let base { Task { await uploader.upload(scanDir: dir, scanId: scanId, base: base) } }
                }
            }

            Button { sharing = true } label: { Label("Share…", systemImage: "square.and.arrow.up") }
        } header: {
            Text("Send to PC")
        } footer: {
            Text("Retrying skips files the PC already has.")
        }
        .sheet(isPresented: $sharing) { ShareSheet(items: [dir]) }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
