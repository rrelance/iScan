import ARKit
import RealityKit
import ScanKit
import UIKit

enum DetailCaptureError: LocalizedError {
    case notStarted

    var errorDescription: String? { "The detail pass never started." }
}

/// Pass 2: LiDAR mesh, high-res photos with depth, and the world map used later by the AR preview.
final class DetailCaptureController: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var frameCount = 0
    @Published private(set) var trackingMessage: String?
    @Published private(set) var isFinishing = false
    @Published private(set) var sessionError: String?

    private let dir: URL
    private let scanId: String
    private let reuse: ARSession?
    private let roomInfo: Manifest.RoomPassInfo?
    private let createdAt = Date()
    private var session: ARSession?

    // Touched only on the main queue (the ARSession delegate queue).
    private var throttle = CaptureThrottle()
    private var manualRequested = false
    private var autoCapture = true
    private var nextIndex = 1
    private var pendingWrites = 0

    private let writeQueue = DispatchQueue(label: "dev.iscan.frame-writer", qos: .userInitiated)

    private struct DepthSnapshot {
        let mm: [UInt16]
        let conf: [UInt8]
        let width: Int
        let height: Int
        let transform: simd_float4x4
        let intrinsics: simd_float3x3
        let imageResolution: CGSize
    }

    init(dir: URL, scanId: String, reuse: ARSession?, roomInfo: Manifest.RoomPassInfo?) {
        self.dir = dir
        self.scanId = scanId
        self.reuse = reuse
        self.roomInfo = roomInfo
    }

    func start(in view: ARView) {
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        if let format = ARWorldTrackingConfiguration.recommendedVideoFormatForHighResolutionFrameCapturing {
            config.videoFormat = format
        }

        let session: ARSession
        if let reuse {
            // Experimental: keep RoomPlan's world origin by continuing its session without a reset.
            view.session = reuse
            session = reuse
            session.delegate = self
            session.run(config)
        } else {
            session = view.session
            session.delegate = self
            session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }
        self.session = session
    }

    func captureManually() {
        manualRequested = true
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let state = frame.camera.trackingState
        let message = Self.message(for: state)
        if message != trackingMessage { trackingMessage = message }
        guard autoCapture else { return }

        let go: Bool
        if manualRequested {
            go = throttle.forceCapture(time: frame.timestamp)
            if go { manualRequested = false }
        } else {
            var normal = false
            if case .normal = state { normal = true }
            go = throttle.shouldCapture(transform: frame.camera.transform, time: frame.timestamp,
                                        trackingNormal: normal)
        }
        guard go else { return }

        let depth = frame.sceneDepth.map { d -> DepthSnapshot in
            let a = FrameExport.depthArrays(d)
            return DepthSnapshot(mm: a.mm, conf: a.conf, width: a.width, height: a.height,
                                 transform: frame.camera.transform, intrinsics: frame.camera.intrinsics,
                                 imageResolution: frame.camera.imageResolution)
        }
        pendingWrites += 1
        session.captureHighResolutionFrame { [weak self] highRes, _ in
            DispatchQueue.main.async { self?.handle(highRes, fallbackDepth: depth) }
        }
    }

    /// Without this ARKit may restart tracking with a new origin after a screen lock, so later
    /// frames would no longer line up with earlier frames and the mesh.
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        true
    }

    func sessionWasInterrupted(_ session: ARSession) {
        trackingMessage = "Tracking lost: move back to a scanned area"
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        sessionError = error.localizedDescription
    }

    // MARK: Writing

    private func handle(_ frame: ARFrame?, fallbackDepth: DepthSnapshot?) {
        guard let frame else {
            pendingWrites -= 1
            throttle.captureFinished()
            return
        }
        let index = nextIndex
        nextIndex += 1
        // Prefer depth from the high-res frame itself; otherwise use the regular frame that triggered it.
        let depth = frame.sceneDepth.map { d -> DepthSnapshot in
            let a = FrameExport.depthArrays(d)
            return DepthSnapshot(mm: a.mm, conf: a.conf, width: a.width, height: a.height,
                                 transform: frame.camera.transform, intrinsics: frame.camera.intrinsics,
                                 imageResolution: frame.camera.imageResolution)
        } ?? fallbackDepth
        let image = frame.capturedImage
        let camera = frame.camera
        let metadata = FrameMetadata(
            index: index,
            timestamp: frame.timestamp,
            imageResolution: [Int(camera.imageResolution.width), Int(camera.imageResolution.height)],
            intrinsics: flatten(camera.intrinsics),
            cameraTransform: flatten(camera.transform),
            depthResolution: depth.map { [$0.width, $0.height] },
            depthIntrinsics: depth.map {
                flatten(scaleIntrinsics($0.intrinsics,
                                        from: SIMD2(Float($0.imageResolution.width), Float($0.imageResolution.height)),
                                        to: SIMD2(Float($0.width), Float($0.height))))
            },
            depthTransform: depth.map { flatten($0.transform) },
            trackingState: Self.name(for: camera.trackingState)
        )
        let dir = dir
        writeQueue.async { [weak self] in
            let paths = BundleLayout.framePaths(index: index)
            if let jpg = FrameExport.jpeg(from: image) {
                try? jpg.write(to: dir.appendingPathComponent(paths.jpg))
            }
            if let json = try? JSONEncoder().encode(metadata) {
                try? json.write(to: dir.appendingPathComponent(paths.json))
            }
            if let depth {
                try? DepthPNG.write16(depth.mm, width: depth.width, height: depth.height,
                                      to: dir.appendingPathComponent(paths.depth))
                try? DepthPNG.write8(depth.conf, width: depth.width, height: depth.height,
                                     to: dir.appendingPathComponent(paths.conf))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingWrites -= 1
                self.frameCount += 1
                self.throttle.captureFinished()
            }
        }
    }

    // MARK: Finish

    /// Stops capturing and keeps whatever is already on disk (the scan shows as Incomplete).
    func cancel() {
        autoCapture = false
        session?.pause()
    }

    /// Safe to call again after a failure; a second tap while finishing is ignored.
    @MainActor
    func finish() async throws -> Manifest? {
        guard !isFinishing else { return nil }
        guard let session else { throw DetailCaptureError.notStarted }
        autoCapture = false
        isFinishing = true
        defer { isFinishing = false }
        while pendingWrites > 0 {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        if let map = await withCheckedContinuation({ (c: CheckedContinuation<ARWorldMap?, Never>) in
            session.getCurrentWorldMap { map, _ in c.resume(returning: map) }
        }), let data = try? NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true) {
            try? data.write(to: dir.appendingPathComponent(BundleLayout.worldMap))
        }

        let anchors = session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
        session.pause()

        let draft = Manifest(scanId: scanId, createdAt: createdAt, device: Self.deviceModel(),
                             systemVersion: UIDevice.current.systemVersion, sessionReused: reuse != nil,
                             roomPass: roomInfo, detailPass: Manifest.DetailPassInfo(frameCount: 0, meshFaceCount: 0))
        let dir = dir
        let manifest = try await Task.detached(priority: .userInitiated) {
            try BundleFinalizer.finalize(dir: dir, manifest: draft, meshChunks: anchors.map(FrameExport.meshChunk))
        }.value
        return manifest
    }

    // MARK: Helpers

    private static func message(for state: ARCamera.TrackingState) -> String? {
        switch state {
        case .normal:
            return nil
        case .limited(.excessiveMotion):
            return "Slow down"
        case .limited(.insufficientFeatures):
            return "Not enough detail here: point at textured surfaces"
        case .limited:
            return "Tracking lost: move back to a scanned area"
        case .notAvailable:
            return "Tracking unavailable"
        }
    }

    private static func name(for state: ARCamera.TrackingState) -> String {
        switch state {
        case .normal: return "normal"
        case .limited(let reason): return "limited:\(reason)"
        case .notAvailable: return "notAvailable"
        }
    }

    private static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
