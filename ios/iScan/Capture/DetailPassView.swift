import RealityKit
import ScanKit
import SwiftUI

private struct DetailARView: UIViewRepresentable {
    let controller: DetailCaptureController

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.debugOptions = [.showSceneUnderstanding]
        controller.start(in: view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

/// Pass 2 UI: live mesh overlay, photo counter, shutter and Finish.
struct DetailPassView: View {
    @StateObject private var controller: DetailCaptureController
    let onFinished: (Manifest) -> Void

    @State private var showHint = true
    @State private var finishError: String?

    init(controller: @autoclosure @escaping () -> DetailCaptureController, onFinished: @escaping (Manifest) -> Void) {
        _controller = StateObject(wrappedValue: controller())
        self.onFinished = onFinished
    }

    var body: some View {
        ZStack {
            DetailARView(controller: controller).ignoresSafeArea()
            VStack(spacing: 8) {
                if showHint {
                    banner("Pass 2 of 2: walk slowly around every piece of equipment, then sweep the ceiling for beams and ducts.")
                }
                if let message = controller.trackingMessage {
                    banner(message, color: .orange)
                }
                if let error = controller.sessionError ?? finishError {
                    banner(error, color: .red)
                }
                Spacer()
                bottomBar
            }
            .padding()
            if controller.isFinishing {
                ProgressView("Saving scan…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            withAnimation { showHint = false }
        }
    }

    private var bottomBar: some View {
        HStack {
            Label("\(controller.frameCount)", systemImage: "photo.stack")
                .font(.headline.monospacedDigit())
                .padding(10)
                .background(.ultraThinMaterial, in: Capsule())
            Spacer()
            Button(action: controller.captureManually) {
                Circle().strokeBorder(.white, lineWidth: 4).frame(width: 64, height: 64)
                    .background(Circle().fill(.white.opacity(0.3)))
            }
            .accessibilityLabel("Take photo")
            Spacer()
            Button("Finish") {
                Task {
                    do { onFinished(try await controller.finish()) } catch { finishError = error.localizedDescription }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(controller.isFinishing)
        }
    }

    private func banner(_ text: String, color: Color = .primary) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
