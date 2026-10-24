import ARKit
import RoomPlan
import ScanKit
import SwiftUI

enum CaptureStep {
    case room, detail, review
}

/// One scan: room pass → detail pass → review.
struct CaptureFlowView: View {
    @EnvironmentObject private var store: ScanStore
    @Environment(\.dismiss) private var dismiss

    @State private var scan: (id: String, dir: URL)?
    @State private var step: CaptureStep = .room
    @State private var roomInfo: Manifest.RoomPassInfo?
    @State private var roomSession: ARSession?
    @State private var errorMessage: String?
    @State private var manifest: Manifest?
    @AppStorage("reuseRoomSession") private var reuseRoomSession = false

    var body: some View {
        Group {
            if let scan {
                switch step {
                case .room:
                    RoomPassView(onFinish: { room, session in finishRoom(room, session: session, dir: scan.dir) },
                                 onSkip: { step = .detail },
                                 onCancel: cancel)
                case .detail:
                    DetailPassView(controller: DetailCaptureController(dir: scan.dir, scanId: scan.id,
                                                                       reuse: reuseRoomSession ? roomSession : nil,
                                                                       roomInfo: roomInfo),
                                   onFinished: { manifest = $0; step = .review },
                                   onCancel: { dismiss() })
                case .review:
                    if let manifest {
                        ReviewView(manifest: manifest, dir: scan.dir, onDone: { dismiss() })
                    }
                }
            } else {
                ProgressView()
            }
        }
        .alert("Couldn't save the room", isPresented: Binding(get: { errorMessage != nil },
                                                              set: { if !$0 { errorMessage = nil } })) {
            Button("Continue anyway") { step = .detail }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            if scan == nil {
                do { scan = try store.newScanDir() } catch { errorMessage = error.localizedDescription }
            }
        }
    }

    private func finishRoom(_ room: CapturedRoom, session: ARSession, dir: URL) {
        roomSession = session
        roomInfo = Manifest.RoomPassInfo(surfaceCount: room.walls.count + room.doors.count + room.windows.count
                                             + room.openings.count,
                                         objectCount: room.objects.count)
        do {
            try RoomExport.write(room, to: dir)
            step = .detail
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancel() {
        if let scan { try? FileManager.default.removeItem(at: scan.dir) }
        dismiss()
    }
}
