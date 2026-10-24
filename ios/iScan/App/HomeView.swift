import SwiftUI
import ScanKit

struct HomeView: View {
    @EnvironmentObject private var store: ScanStore
    @State private var capturing = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                if store.scans.isEmpty {
                    Text("No scans yet. Tap New Scan and walk around your gym.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.scans) { scan in
                    NavigationLink {
                        ScanSummaryList(scanId: scan.id, dir: scan.dir, manifest: scan.manifest)
                            .navigationTitle(scan.id)
                    } label: {
                        ScanRow(scan: scan)
                    }
                }
                .onDelete { offsets in offsets.map { store.scans[$0] }.forEach(store.delete) }
            }
            .navigationTitle("iScan")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { capturing = true } label: {
                    Label("New Scan", systemImage: "viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
            .refreshable { store.reload() }
        }
        .fullScreenCover(isPresented: $capturing, onDismiss: store.reload) {
            CaptureFlowView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

private struct ScanRow: View {
    let scan: ScanEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(scan.id).font(.headline.monospacedDigit())
            if let m = scan.manifest {
                Text("\(m.detailPass.frameCount) photos · \(m.detailPass.meshFaceCount) mesh faces"
                     + (m.roomPass == nil ? " · room pass skipped" : ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Incomplete").font(.subheadline).foregroundStyle(.orange)
            }
        }
    }
}
