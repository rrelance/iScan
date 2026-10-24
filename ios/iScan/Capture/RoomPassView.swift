import ARKit
import RoomPlan
import SwiftUI

/// Owns the RoomPlan capture view and tracks where the pass is.
final class RoomCaptureModel: NSObject, ObservableObject, RoomCaptureViewDelegate {
    enum State {
        case scanning
        case processing
        case presented(CapturedRoom)
        case failed(String)
    }

    @Published var state: State = .scanning
    let captureView = RoomCaptureView(frame: .zero)

    override init() {
        super.init()
        captureView.delegate = self
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func encode(with coder: NSCoder) {}

    func start() {
        captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }

    func stop() {
        state = .processing
        captureView.captureSession.stop()
    }

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        DispatchQueue.main.async {
            if let error {
                self.state = .failed(error.localizedDescription)
            } else {
                self.state = .presented(processedResult)
            }
        }
    }
}

private struct RoomCaptureContainer: UIViewRepresentable {
    let model: RoomCaptureModel

    func makeUIView(context: Context) -> RoomCaptureView {
        model.captureView
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}

/// Pass 1: RoomPlan walls, doors, windows and recognized objects.
struct RoomPassView: View {
    /// Called with the finished room and RoomPlan's AR session (for the experimental session reuse).
    let onFinish: (CapturedRoom, ARSession) -> Void
    let onSkip: () -> Void
    let onCancel: () -> Void

    @StateObject private var model = RoomCaptureModel()

    var body: some View {
        ZStack {
            RoomCaptureContainer(model: model).ignoresSafeArea()
            VStack {
                HStack {
                    Button("Cancel", action: onCancel)
                    Spacer()
                    Button("Skip room pass", action: onSkip)
                }
                .padding()
                .background(.ultraThinMaterial)
                Spacer()
                controls.padding()
            }
        }
        .onAppear { model.start() }
    }

    @ViewBuilder
    private var controls: some View {
        switch model.state {
        case .scanning:
            VStack(spacing: 8) {
                Text("Pass 1 of 2: walk the edges of the gym so the walls, doors and windows are captured.")
                    .font(.callout).multilineTextAlignment(.center)
                Button("Done") { model.stop() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .processing:
            ProgressView("Building room…").padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .presented(let room):
            Button("Continue to detail pass") { onFinish(room, model.captureView.captureSession.arSession) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        case .failed(let message):
            VStack(spacing: 8) {
                Text("RoomPlan couldn't finish: \(message)").multilineTextAlignment(.center)
                Button("Skip room pass", action: onSkip).buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
