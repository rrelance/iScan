import Foundation
import ScanKit

struct ScanEntry: Identifiable {
    let id: String
    let dir: URL
    let manifest: Manifest?
}

/// Scan bundles in `Documents/scans/<id>/` (also visible in the Files app).
final class ScanStore: ObservableObject {
    @Published private(set) var scans: [ScanEntry] = []
    let root: URL

    init() {
        root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scans", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
    }

    func newScanDir() throws -> (id: String, dir: URL) {
        let id = BundleLayout.scanId(for: Date())
        let dir = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(BundleLayout.framesDir),
                                                withIntermediateDirectories: true)
        return (id, dir)
    }

    func reload() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        scans = names.filter(BundleLayout.isValidScanId).sorted(by: >).map { id in
            let dir = root.appendingPathComponent(id, isDirectory: true)
            let manifest = (try? Data(contentsOf: dir.appendingPathComponent(BundleLayout.manifest)))
                .flatMap { try? Manifest.decoder().decode(Manifest.self, from: $0) }
            return ScanEntry(id: id, dir: dir, manifest: manifest)
        }
    }

    func delete(_ entry: ScanEntry) {
        try? FileManager.default.removeItem(at: entry.dir)
        reload()
    }
}
