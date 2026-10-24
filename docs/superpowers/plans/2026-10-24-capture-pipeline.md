# iScan Capture Pipeline Implementation Plan (Plan 1 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scan the gym with the iPhone and get a complete, aligned scan bundle onto the PC in `scans/<id>/`.

**Architecture:** A SwiftUI app (built unsigned on GitHub Actions, installed via TrollStore) runs a RoomPlan pass and then an ARKit detail pass. It writes a bundle to the app's Documents folder and uploads it file by file to a Fastify server on the PC. The device-independent logic lives in a pure Swift package (`ScanKit`), unit-tested on the CI macOS runner. A Python tool aligns the RoomPlan walls to the detail-pass mesh.

**Tech Stack:** Swift 5 / SwiftUI / RoomPlan / ARKit / RealityKit, XcodeGen, ldid, GitHub Actions (`macos-latest`); Node 24 + TypeScript + Fastify 5 + vitest + bonjour-service; Python 3.13 + numpy + plyfile + pytest.

**Spec:** `docs/superpowers/specs/2026-10-24-iscan-design.md` (sections 1–3, alignment in 4, milestones 0–2).

**Later plans:** 2) modeling tools + first gym model, 3) planner + Claude layouts, 4) AR preview.

**Changes from the spec (settled here):**
- **Upload is per-file, resumable** (`PUT` each file, then `POST complete`) instead of one zip. This removes the need for a zip library on the phone and makes retries over Wi-Fi cheap.
- **Share-sheet fallback:** the app also enables Files-app access (`UIFileSharingEnabled`) as an extra fallback.
- **`walls.json`:** the app writes a `walls.json` in our own schema next to the raw `room.json`, because `CapturedRoom`'s Codable layout is Apple-private and may change.
- **Rolling `nightly` release:** CI publishes to a rolling `nightly` release on every push to `main`, giving the phone a stable download URL.

## Global Constraints

- iOS deployment target **16.0**. The device is an iPhone 12 Pro Max on iOS 16.4.1. **No iOS 17+ APIs** (e.g. no `RoomCaptureSession(arSession:)`, no `CapturedRoom.export(to:exportOptions:)`).
- `SWIFT_VERSION = 5.0` (avoids Swift 6 strict-concurrency churn).
- Bundle id `dev.iscan.app`. App name `iScan`. No personal names or emails anywhere in code or config.
- Units: meters everywhere. ARKit world frame is gravity-aligned, +Y up.
- Scan id format `yyyyMMdd-HHmmss` (local time), regex `^\d{8}-\d{6}$`.
- Server listens on `0.0.0.0:8787`. Bonjour service type `_iscan._tcp`.
- Repo is **public** on GitHub. `scans/` is gitignored.
- Bundle layout (exact paths, relative to the scan dir):
  - `manifest.json`, `room.json`, `room.usdz`, `walls.json`, `mesh.ply`, `worldmap.arworldmap`
  - `frames/NNNN.jpg`, `frames/NNNN.json`, `frames/NNNN_depth.png`, `frames/NNNN_conf.png` (4-digit, 1-based)
- ARMeshClassification codes written to `mesh.ply`: none 0, wall 1, floor 2, ceiling 3, table 4, seat 5, window 6, door 7.
- iOS code cannot be compiled on the Windows PC. **Swift tests run only in CI** (`swift test` on `macos-latest`), so a red/green cycle means push → watch the Actions run.

## Review Focus

1. **Detail pass interrupted** (phone call, screen lock, tracking lost): already-captured frames stay on disk, capture pauses while tracking isn't `.normal`, and Finish still writes a valid bundle. Pinned by the `CaptureThrottle` tests (Task 2) and the `BundleFinalizer` zero-frame test (Task 3).
2. **Memory pressure from hundreds of high-res frames:** at most one high-res capture in flight, and pixel buffers are never retained after encoding. Pinned by the `CaptureThrottle` in-flight test (Task 2).
3. **Upload dies halfway** (Wi-Fi drop, firewall): a re-upload skips files already on the server, `.partial` files never count as present, and the app's error names the firewall when the host is unreachable. Pinned by the server partial-file test (Task 6) and the `UploadPlan` resume test (Task 7).
4. **Hostile or malformed upload paths** (`..`, absolute, encoded traversal, bad scan id) are rejected with 400 and nothing is written outside `scans/<id>/`. Pinned by the server tests (Task 6).
5. **Open basement with few walls** (RoomPlan finds 0–1 walls, or the user skips the room pass): the detail pass still works, and `align.py` fails with a clear `AlignmentError` message instead of a bogus transform. Pinned by the Task 8 tests.

---

### Task 1: Repo bootstrap + CI-built hello-world IPA (Milestone 0)

**Files:**
- Create: `.gitignore`, `README.md`, `ios/project.yml`, `ios/iScan.entitlements`, `ios/iScan/App/iScanApp.swift`, `.github/workflows/ios.yml`
- Create: `ios/ScanKit/Package.swift`, `ios/ScanKit/Sources/ScanKit/ScanKit.swift`, `ios/ScanKit/Tests/ScanKitTests/SmokeTests.swift`

**Interfaces:**
- Produces: the XcodeGen target `iScan` (sources `ios/iScan/**`, local package dependency `ScanKit`); the CI jobs `scankit-tests` and `build-ipa`; the release download URL `https://github.com/<owner>/iScan/releases/download/nightly/iScan.ipa`.

- [ ] **Step 1: `git init`**, then write the following and commit them along with the existing `docs/`:
  - `.gitignore`: `scans/`, `node_modules/`, `ios/*.xcodeproj`, `ios/build/`, `__pycache__/`, `.venv/`, `*.partial`, `.DS_Store`, `.build/`
  - `README.md`: one paragraph plus a "Install on phone" section with the nightly URL
- [ ] **Step 2: Write `ios/ScanKit/Package.swift`**: library `ScanKit`, platforms `.iOS(.v16), .macOS(.v13)`, test target `ScanKitTests`. Add the smoke test `testVersion() { XCTAssertEqual(ScanKit.schemaVersion, 1) }` and `public enum ScanKit { public static let schemaVersion = 1 }`.
- [ ] **Step 3: Write `ios/project.yml`**:
  - target `iScan` (application, iOS 16.0), `PRODUCT_BUNDLE_IDENTIFIER: dev.iscan.app`, `SWIFT_VERSION: 5.0`, `CODE_SIGNING_ALLOWED: NO`, package `ScanKit: {path: ScanKit}`
  - `info:` generates `iScan/Info.plist` with:
    - `NSCameraUsageDescription`: "iScan uses the camera and LiDAR to scan your gym."
    - `NSLocalNetworkUsageDescription`: "iScan uploads scans to your PC on this network."
    - `NSBonjourServices: [_iscan._tcp]`
    - `NSAppTransportSecurity: {NSAllowsLocalNetworking: true, NSAllowsArbitraryLoads: true}`
    - `UIRequiredDeviceCapabilities: [arkit]`
    - `UIFileSharingEnabled: true`, `LSSupportsOpeningDocumentsInPlace: true`
    - `UILaunchScreen: {}`
- [ ] **Step 4: Write `iScanApp.swift`** (`@main` app with a `Text("iScan")` view) and `iScan.entitlements` (a plist containing only `application-identifier` = `dev.iscan.app`).
- [ ] **Step 5: Write `.github/workflows/ios.yml`.**
  - Triggers: `push` to `main`, tags `v*`, `workflow_dispatch`. `permissions: contents: write`.
  - Job `scankit-tests` (`macos-latest`): `swift test --package-path ios/ScanKit`.
  - Job `build-ipa` (`needs: scankit-tests`):
    1. `brew install xcodegen ldid`
    2. `cd ios && xcodegen generate`
    3. `xcodebuild -project iScan.xcodeproj -scheme iScan -sdk iphoneos -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build`
    4. Copy `build/Build/Products/Release-iphoneos/iScan.app` into `Payload/`.
    5. `ldid -Sios/iScan.entitlements Payload/iScan.app/iScan` (sign the **binary**).
    6. `zip -qry iScan.ipa Payload`
    7. `actions/upload-artifact@v4`
    8. On `main`: `gh release view nightly || gh release create nightly --prerelease --title nightly --notes "Rolling build"`, then `gh release upload nightly iScan.ipa --clobber`.
    9. On tags: `gh release create $GITHUB_REF_NAME iScan.ipa`.
    - Steps 8 and 9 need `GH_TOKEN: ${{ github.token }}`.
- [ ] **Step 6: Create the GitHub repo and push.** The `gh` CLI isn't installed, so ask the user to create an empty **public** repo named `iScan` on github.com and paste its URL. Then `git remote add origin <url>`, `git branch -M main`, `git push -u origin main`.
- [ ] **Step 7: Verify CI.** The Actions run shows both jobs green, and the `nightly` release has `iScan.ipa`. On failure, read the job log and fix before continuing.
- [ ] **Step 8: User check.** The user opens the nightly URL in Safari on the phone, then Share → TrollStore → Install. The app launches and shows "iScan". **Do not proceed until confirmed.**

---

### Task 2: ScanKit core (bundle layout, manifest, intrinsics, capture throttle)

**Files:**
- Create: `ios/ScanKit/Sources/ScanKit/BundleLayout.swift`, `Manifest.swift`, `FrameMetadata.swift`, `CaptureThrottle.swift`
- Test: `ios/ScanKit/Tests/ScanKitTests/BundleLayoutTests.swift`, `ManifestTests.swift`, `FrameMetadataTests.swift`, `CaptureThrottleTests.swift`

**Interfaces:**
- Produces:
  - `enum BundleLayout`
    - `static func scanId(for date: Date, timeZone: TimeZone = .current) -> String`
    - `static func isValidScanId(_ s: String) -> Bool`
    - `static func framePaths(index: Int) -> (jpg: String, json: String, depth: String, conf: String)`
    - `static let manifest = "manifest.json", roomJSON = "room.json", roomUSDZ = "room.usdz", walls = "walls.json", mesh = "mesh.ply", worldMap = "worldmap.arworldmap"`
  - `struct Manifest: Codable, Equatable`
    - `{ schemaVersion: Int; scanId: String; createdAt: Date; device: String; systemVersion: String; units: String; sessionReused: Bool; roomPass: RoomPassInfo?; detailPass: DetailPassInfo }`
    - Nested types (referenced elsewhere as `Manifest.RoomPassInfo` and `Manifest.DetailPassInfo`): `RoomPassInfo: Codable, Equatable { surfaceCount: Int; objectCount: Int }` and `DetailPassInfo: Codable, Equatable { frameCount: Int; meshFaceCount: Int }`
    - `static func encoder() -> JSONEncoder` (ISO8601 dates, sorted keys, pretty) and `static func decoder() -> JSONDecoder`
  - `struct FrameMetadata: Codable`
    - `{ index: Int; timestamp: Double; imageResolution: [Int]; intrinsics: [Float]; cameraTransform: [Float]; depthResolution: [Int]?; depthIntrinsics: [Float]?; depthTransform: [Float]?; trackingState: String }`
    - Matrices are flattened column-major (9 or 16 floats).
  - `func scaleIntrinsics(_ k: simd_float3x3, from: SIMD2<Float>, to: SIMD2<Float>) -> simd_float3x3`
  - `func flatten(_ m: simd_float3x3) -> [Float]`, `func flatten(_ m: simd_float4x4) -> [Float]`
  - `struct CaptureThrottle`
    - `init(minTranslation: Float = 0.5, minRotationDegrees: Float = 20, minInterval: TimeInterval = 0.7)`
    - `mutating func shouldCapture(transform: simd_float4x4, time: TimeInterval, trackingNormal: Bool) -> Bool` (true marks the capture as in flight and records the pose)
    - `mutating func captureFinished()`

- [ ] **Step 1: Write failing tests:**
  - `BundleLayoutTests`:
    - `scanId(for: 2026-10-24 14:05:09 UTC, timeZone: UTC) == "20261024-140509"`
    - `isValidScanId` is true for that value and false for `"2026-10-24"`, `"../x"`, and `""`
    - `framePaths(index: 7).jpg == "frames/0007.jpg"`, `.depth == "frames/0007_depth.png"`
  - `ManifestTests`: an encode→decode round trip is equal; the encoded JSON contains `"units" : "meters"` and an ISO8601 `createdAt`.
  - `FrameMetadataTests`:
    - K with fx=fy=1500, cx=960, cy=720, scaled from (1920,1440) to (256,192), gives fx=fy=200, cx=128, cy=96 (accuracy 1e-3)
    - `flatten(simd_float4x4)` of a translation (1,2,3) has elements 12,13,14 == 1,2,3
  - `CaptureThrottleTests`:
    - the first call with `trackingNormal: true` returns true
    - a second call before `captureFinished()` returns false (**in flight**)
    - after finishing: a move of 0.3 m returns false; 0.6 m at t+1 s returns true
    - a 25° yaw at the same position returns true
    - a 0.6 m move at t+0.2 s returns false (min interval)
    - `trackingNormal: false` always returns false
- [ ] **Step 2: Push and confirm the `scankit-tests` job FAILS** (compile errors for the missing symbols).
- [ ] **Step 3: Implement the four files.** Rotation angle = `acos((trace(R_rel) - 1)/2)` on the relative 3×3, clamped to [-1, 1].
- [ ] **Step 4: Push and confirm `scankit-tests` passes.**
- [ ] **Step 5: Commit** `feat(scankit): bundle layout, manifest, intrinsics, capture throttle`.

---

### Task 3: ScanKit writers (PLY mesh, depth PNG, walls summary, finalizer)

**Files:**
- Create: `ios/ScanKit/Sources/ScanKit/PLYWriter.swift`, `DepthPNG.swift`, `RoomSummary.swift`, `BundleFinalizer.swift`
- Test: `ios/ScanKit/Tests/ScanKitTests/PLYWriterTests.swift`, `DepthPNGTests.swift`, `RoomSummaryTests.swift`, `BundleFinalizerTests.swift`

**Interfaces:**
- Consumes: `BundleLayout`, `Manifest` (Task 2).
- Produces:
  - `struct MeshChunk { vertices: [SIMD3<Float>]; faces: [SIMD3<UInt32>]; classification: [UInt8] }` (world-space; one classification per face)
  - `enum PLYWriter`
    - `static func header(vertexCount: Int, faceCount: Int) -> String`
    - `static func write(_ chunks: [MeshChunk], to url: URL) throws -> (vertices: Int, faces: Int)`
  - `enum DepthPNG`
    - `static func millimeters(fromMeters: [Float]) -> [UInt16]`
    - `static func write16(_ px: [UInt16], width: Int, height: Int, to url: URL) throws`
    - `static func write8(_ px: [UInt8], width: Int, height: Int, to url: URL) throws`
  - `struct SurfaceRecord: Codable, Equatable { kind: String; category: String; transform: [Float]; dimensions: [Float]; confidence: String }`
  - `struct RoomSummary: Codable, Equatable { schemaVersion: Int; walls: [SurfaceRecord]; doors: [SurfaceRecord]; windows: [SurfaceRecord]; openings: [SurfaceRecord]; objects: [SurfaceRecord] }`
  - `enum BundleFinalizer { static func finalize(dir: URL, manifest: Manifest, meshChunks: [MeshChunk]) throws -> Manifest }` (writes `mesh.ply`, fills `detailPass.meshFaceCount`, counts `frames/*.jpg` for `frameCount`, writes `manifest.json`, returns the final manifest)

- [ ] **Step 1: Write failing tests:**
  - `PLYWriterTests`:
    - the header equals exactly:
      ```
      ply
      format binary_little_endian 1.0
      element vertex V
      property float x
      property float y
      property float z
      element face F
      property list uchar uint vertex_indices
      property uchar classification
      end_header
      ```
      (with a trailing `\n`)
    - two chunks (3 vertices/1 face, 4 vertices/2 faces) write V=7, F=3
    - the file size is `header.utf8.count + 7*12 + 3*(1+12+1)`
    - the second chunk's first face indices are offset by 3 (read back from bytes)
  - `DepthPNGTests`:
    - `millimeters(fromMeters: [1.234, .nan, -1, 70])` == `[1234, 0, 0, 65535]`
    - a 4×3 `write16` round-trips through `CGImageSourceCreateWithURL` with the same 16-bit values and `bitsPerComponent == 16`
  - `RoomSummaryTests`: an encode/decode round trip; a wall's `dimensions.count == 3` and `transform.count == 16`.
  - `BundleFinalizerTests`:
    - in a temp dir with 2 dummy `frames/*.jpg`, `finalize` writes `manifest.json` (frameCount 2) and `mesh.ply`
    - **zero frames + zero chunks** still writes a valid manifest (frameCount 0, meshFaceCount 0) and a PLY with V=0, F=0
- [ ] **Step 2: Push and confirm the tests FAIL.**
- [ ] **Step 3: Implement.** `DepthPNG` uses ImageIO (`CGImageDestinationCreateWithURL`, `kUTTypePNG`) with a grayscale `CGImage`; 16-bit uses `CGBitmapInfo.byteOrder16Little`.
- [ ] **Step 4: Push and confirm `scankit-tests` passes.**
- [ ] **Step 5: Commit** `feat(scankit): PLY, depth PNG, room summary, bundle finalizer`.

---

### Task 4: iOS app shell + room pass

**Files:**
- Create: `ios/iScan/App/HomeView.swift`, `ios/iScan/App/ScanStore.swift`, `ios/iScan/Capture/CaptureFlowView.swift`, `ios/iScan/Capture/RoomPassView.swift`, `ios/iScan/Export/RoomExport.swift`
- Modify: `ios/iScan/App/iScanApp.swift`

**Interfaces:**
- Consumes: `BundleLayout`, `RoomSummary`, `SurfaceRecord` (Tasks 2–3).
- Produces:
  - `final class ScanStore: ObservableObject`
    - `@Published var scans: [ScanEntry]`, with `ScanEntry { id: String; dir: URL; manifest: Manifest? }`
    - `func newScanDir() throws -> (id: String, dir: URL)` (creates `Documents/scans/<id>/frames/`)
    - `func reload()`
  - `enum RoomExport { static func summary(_ room: CapturedRoom) -> RoomSummary; static func write(_ room: CapturedRoom, to dir: URL) throws }`
    - `write` produces `room.json` via `JSONEncoder`, `room.usdz` via `export(to:)`, and `walls.json`
  - `enum CaptureStep { case room, detail, review }`
  - `struct CaptureFlowView` holds the scan id/dir, the step, and an optional `CapturedRoom`. It passes `RoomCaptureSession.arSession` forward for the experimental reuse option.

- [ ] **Step 1: Implement `ScanStore` and `HomeView`.**
  - `HomeView`: a list of scans (id, frame count from the manifest, or "incomplete"), a **New Scan** button, and a toolbar gear icon (Settings placeholder for Task 7).
- [ ] **Step 2: Implement `RoomPassView`** as a `UIViewRepresentable` around `RoomCaptureView`.
  - Coordinator conforms to `RoomCaptureViewDelegate` (`NSCoding` stubs) and returns `true` from `captureView(shouldPresent:error:)`.
  - It receives the `CapturedRoom` in `captureView(didPresent:error:)`.
  - Buttons:
    - **Done:** `captureSession.stop()`, then present the result.
    - **Skip room pass:** goes to the detail pass with no room (the open-basement fallback).
  - On an error, show it and offer Skip.
- [ ] **Step 3: Implement `RoomExport`.** Each `CapturedRoom.Surface`/`Object` maps to a `SurfaceRecord` (`category` = `String(describing:)`, `transform` = `flatten`, `dimensions` = `[x, y, z]`, `confidence` = `String(describing:)`).
- [ ] **Step 4: Wire `CaptureFlowView`.** room → (writes the room files) → detail (placeholder `Text` until Task 5).
- [ ] **Step 5: Push. CI is green and the nightly IPA is updated.**
- [ ] **Step 6: User check on the phone.**
  - New Scan → RoomPlan UI appears → scan the gym → Done.
  - In the Files app, "On My iPhone › iScan › scans › <id>" contains `room.json`, `room.usdz`, and `walls.json`. Opening `room.usdz` in Files Quick Look shows the room.
  - Skip also works.
- [ ] **Step 7: Commit** `feat(ios): app shell and RoomPlan room pass`.

---

### Task 5: iOS detail pass (mesh, high-res frames, depth, world map)

**Files:**
- Create: `ios/iScan/Capture/DetailCaptureController.swift`, `ios/iScan/Capture/DetailPassView.swift`, `ios/iScan/Capture/ReviewView.swift`, `ios/iScan/Export/FrameExport.swift`
- Modify: `ios/iScan/Capture/CaptureFlowView.swift`

**Interfaces:**
- Consumes: `CaptureThrottle`, `FrameMetadata`, `scaleIntrinsics`, `flatten`, `DepthPNG`, `MeshChunk`, `BundleFinalizer`, `Manifest`, `BundleLayout`.
- Produces:
  - `final class DetailCaptureController: NSObject, ObservableObject, ARSessionDelegate`
    - `init(dir: URL, scanId: String, reuse: ARSession?, roomInfo: Manifest.RoomPassInfo?)` (`roomInfo == nil` means the room pass was skipped)
    - `@Published frameCount: Int`, `trackingMessage: String?`, `isFinishing: Bool`
    - `func start(in view: ARView)`, `func captureManually()`, `func finish() async throws -> Manifest`
  - `enum FrameExport`
    - `static func jpeg(from: CVPixelBuffer, quality: CGFloat = 0.9) -> Data?` (CIContext)
    - `static func depthArrays(_ d: ARDepthData) -> (mm: [UInt16], conf: [UInt8], width: Int, height: Int)`
    - `static func meshChunk(_ a: ARMeshAnchor) -> MeshChunk` (vertices transformed by `anchor.transform` to world; classification per face, defaulting to 0 when the buffer is absent)

- [ ] **Step 1: Implement `FrameExport`.**
- [ ] **Step 2: Implement `DetailCaptureController`.**
  - **Configuration:** `ARWorldTrackingConfiguration` with `sceneReconstruction = .meshWithClassification`, `frameSemantics = [.sceneDepth]`, and `videoFormat = ARWorldTrackingConfiguration.recommendedVideoFormatForHighResolutionFrameCapturing ?? default`.
  - **Session:** if `reuse` is non-nil (Settings toggle "Reuse RoomPlan session (experimental)", stored in `@AppStorage("reuseRoomSession")`, default off), run that session with no reset options. Otherwise use the ARView's own session.
  - **`session(_:didUpdate:)`:**
    1. Keep the latest `sceneDepth` copied into arrays together with its camera transform. Don't retain the `ARFrame`.
    2. If `throttle.shouldCapture(...)` returns true, call `captureHighResolutionFrame`.
    3. In its completion, on a serial background queue: write the jpg, the metadata (image intrinsics; `depthIntrinsics` = `scaleIntrinsics` to the depth resolution; `depthTransform` = the stored depth pose), and the depth/conf PNGs. Then call `throttle.captureFinished()`.
    4. On a capture error, call `captureFinished()` and continue.
  - **`sessionWasInterrupted` / tracking not normal:** set `trackingMessage` ("Tracking lost: move back to a scanned area"). The throttle already blocks captures.
  - **`finish()`:**
    1. Pause auto-capture and await queue drain.
    2. Call `getCurrentWorldMap` and archive it with `NSKeyedArchiver(requiringSecureCoding: true)` to `worldmap.arworldmap`. If this fails, record it and continue.
    3. Collect `ARMeshAnchor`s from `session.currentFrame?.anchors`.
    4. Call `BundleFinalizer.finalize`.
    5. Pause the session.
- [ ] **Step 3: Implement `DetailPassView`.**
  - `ARView` with `debugOptions = [.showSceneUnderstanding]`, a frame counter, the tracking message banner, a shutter button (`captureManually`), and **Finish**.
  - A hint banner for the first 10 s: "Walk slowly around every piece of equipment, then sweep the ceiling for beams and ducts."
- [ ] **Step 4: Implement `ReviewView`.** Shows frame count, mesh faces, the room-pass surface count or "skipped", and the total size on disk. Buttons: **Upload** (disabled placeholder until Task 7) and **Done** (back to Home, `ScanStore.reload()`).
- [ ] **Step 5: Push. CI is green and the nightly is updated.**
- [ ] **Step 6: User check.**
  - A full scan of the gym (~3–5 min detail pass) finishes without a crash.
  - In Files, the scan folder holds `manifest.json` (frameCount > 50), `mesh.ply`, `worldmap.arworldmap`, and `frames/*` in 4-file groups.
  - Lock and unlock the phone mid-pass once: capture resumes and Finish still works.
  - Copy one scan folder to the PC via Files → OneDrive (or USB) into `scans/<id>/`, to use as sample data for Task 8.
- [ ] **Step 7: Commit** `feat(ios): ARKit detail pass with high-res frames, depth, mesh, world map`.

---

### Task 6: PC upload server

**Files:**
- Create: `server/package.json`, `server/tsconfig.json`, `server/src/scans.ts`, `server/src/app.ts`, `server/src/index.ts`, `server/test/scans.test.ts`
- Create: a root `package.json` with scripts `"server": "npm --prefix server run start"` and `"test": "npm --prefix server test"`

**Interfaces:**
- Produces:
  - `scans.ts`
    - `isValidScanId(id: string): boolean`
    - `resolveScanPath(scansDir: string, id: string, rel: string): string | null` (null when invalid; each segment matches `^[A-Za-z0-9_-][A-Za-z0-9._-]*$`, no `..`, depth ≤ 3, and the result stays inside `scansDir/id`)
    - `listFiles(scanDir: string): Promise<{ path: string; size: number }[]>` (posix-style relative paths, excludes `*.partial` and `.complete`)
  - `app.ts`: `buildApp(opts: { scansDir: string }): FastifyInstance`
  - HTTP:
    - `GET /api/health` → `{ ok: true, name: "iscan" }`
    - `GET /api/scans` → `[{ id, complete: boolean, fileCount }]`
    - `GET /api/scans/:id/status` → `{ files: [{path,size}] }`
    - `PUT /api/scans/:id/files/*` (body `application/octet-stream`, streamed to `<path>.partial` and then renamed) → `{ ok: true, size }`
    - `POST /api/scans/:id/complete` with body `{ files: [{path,size}] }` → 200 `{ ok: true, fileCount }` (and writes `.complete`), or 409 `{ missing: string[] }` (listing files that are absent or the wrong size)
  - `index.ts`:
    - scans dir = `<repo>/scans`; listen `0.0.0.0:8787`
    - publish Bonjour `{ name: "iScan", type: "iscan", port: 8787 }` via `bonjour-service`, logging and continuing on error
    - print each LAN IPv4 URL and these two commands:
      ```
      New-NetFirewallRule -DisplayName "iScan TCP 8787" -Direction Inbound -Protocol TCP -LocalPort 8787 -Action Allow -Profile Private
      New-NetFirewallRule -DisplayName "iScan mDNS" -Direction Inbound -Protocol UDP -LocalPort 5353 -Action Allow -Profile Private
      ```

- [ ] **Step 1: Write failing vitest tests** (`app.inject`, temp `scansDir`):
  - health returns ok
  - PUT `frames/0001.jpg` (5 MB buffer) → 200, then status lists it with size 5242880
  - a PUT with path `../../evil`, `%2e%2e/evil`, `/abs`, `.hidden`, or `a/b/c/d/e` → 400, and nothing exists outside the scan dir
  - scan id `2026-10-24` → 400
  - **a leftover `manifest.json.partial` in the dir is not listed by status**
  - complete with a missing file → 409 `{missing:["mesh.ply"]}`; after uploading it → 200, `.complete` exists, and `GET /api/scans` shows `complete: true`
  - re-PUT of the same path overwrites (size updates)
- [ ] **Step 2:** Run `npm --prefix server test` and confirm the tests FAIL.
- [ ] **Step 3: Implement.** Use `bodyLimit: 1_000_000_000` and an `application/octet-stream` content-type parser that passes the raw stream; write with `stream/promises.pipeline` + `fs.createWriteStream`.
- [ ] **Step 4:** Run the tests and confirm they PASS.
- [ ] **Step 5:** `npm run server`, then `curl http://localhost:8787/api/health` returns `{"ok":true,"name":"iscan"}`.
- [ ] **Step 6: Commit** `feat(server): resumable scan upload API with Bonjour`.

---

### Task 7: iOS upload, discovery, settings

**Files:**
- Create: `ios/ScanKit/Sources/ScanKit/UploadPlan.swift`, `ios/ScanKit/Tests/ScanKitTests/UploadPlanTests.swift`, `ios/iScan/Upload/ServerDiscovery.swift`, `ios/iScan/Upload/Uploader.swift`, `ios/iScan/Settings/SettingsView.swift`
- Modify: `ios/iScan/Capture/ReviewView.swift`, `ios/iScan/App/HomeView.swift` (swipe action: Upload / Share)

**Interfaces:**
- Consumes: the Task 6 HTTP API.
- Produces:
  - `struct UploadFile: Equatable { path: String; size: Int }`
  - `enum UploadPlan`
    - `static func localFiles(in dir: URL) throws -> [UploadFile]` (recursive, posix paths, sorted, skipping dotfiles)
    - `static func pending(local: [UploadFile], remote: [UploadFile]) -> [UploadFile]` (absent or different size, with `manifest.json` always last)
  - `final class ServerDiscovery: ObservableObject` (`@Published servers: [DiscoveredServer { name: String; baseURL: URL }]`; `NWBrowser` for `.bonjour(type: "_iscan._tcp", domain: nil)`, resolved by opening an `NWConnection` and reading `currentPath?.remoteEndpoint` as host:port)
  - `final class Uploader: ObservableObject`
    - `@Published progress: Double`, `state: UploadState`
    - `UploadState { idle, uploading, done, failed(String) }`
    - `func upload(scanDir: URL, scanId: String, base: URL) async`
  - Settings: `@AppStorage("serverURL")` (e.g. `http://192.168.1.20:8787`), `@AppStorage("reuseRoomSession")`

- [ ] **Step 1: Write failing `UploadPlanTests`:**
  - with remote holding `frames/0001.jpg` (same size) and `mesh.ply` (wrong size), `pending` returns `mesh.ply` and the missing files, with `manifest.json` last
  - a remote file matching every local file → empty
- [ ] **Step 2: Push and confirm they FAIL. Implement `UploadPlan`. Push and confirm they pass.**
- [ ] **Step 3: Implement `Uploader`.**
  1. `GET /api/health` (5 s timeout). On failure, set `failed("Can't reach <host>. Is the iScan server running on your PC, and is Windows Firewall allowing port 8787?")`.
  2. `GET status`, then `UploadPlan.pending`.
  3. `PUT` each file with `URLSession.upload(for:fromFile:)`, 3 concurrent, up to 3 retries with 1/2/4 s backoff. Progress is by bytes.
  4. `POST complete`; a 409 re-runs pending once and then fails, listing the missing files.
- [ ] **Step 4: Implement `ServerDiscovery` and `SettingsView`.** Settings shows discovered servers (tap to set `serverURL`), a manual URL field, a **Test connection** button (health check), and the experimental reuse toggle.
- [ ] **Step 5: Wire Review/Home.**
  - Upload button with a progress bar. On a failure, show the message and a Retry button.
  - **Share** uses `UIActivityViewController` with the scan folder URL.
- [ ] **Step 6: Push. CI is green and the nightly is updated.**
- [ ] **Step 7: User check (end-to-end).**
  - Run `npm run server` on the PC and apply the printed firewall rules.
  - The phone's Settings shows "iScan" discovered (or enter the URL manually) → Test connection OK.
  - Upload the Task 5 scan; `scans/<id>/` on the PC matches the phone, and `.complete` exists.
  - Toggle Wi-Fi off mid-upload, back on, then Retry: it completes without re-sending the finished files (watch the server log).
- [ ] **Step 8: Commit** `feat(ios): resumable Wi-Fi upload with Bonjour discovery`.

---

### Task 8: Scan alignment tool (`align.py`) + capture spike verdict

**Files:**
- Create: `tools/requirements.txt` (`numpy`, `plyfile`, `pytest`), `tools/scan_io.py`, `tools/align.py`, `tools/tests/test_align.py`, `tools/tests/conftest.py`

**Interfaces:**
- Consumes: the bundle files `walls.json` (RoomSummary) and `mesh.ply` (Task 3 format).
- Produces:
  - `scan_io.py`
    - `@dataclass Wall(center: np.ndarray, x_axis: np.ndarray, width: float, height: float)`
    - `load_walls(path) -> list[Wall]` (from `walls.json`; transform is column-major 16, column 0 = x axis, column 3 = translation)
    - `load_mesh(path) -> tuple[np.ndarray, np.ndarray, np.ndarray]` (vertices (N,3), faces (M,3), classification (M,))
  - `align.py`
    - `class AlignmentError(Exception)`
    - `@dataclass Alignment(yaw_rad: float, translation: np.ndarray, matrix: np.ndarray, rms: float, inlier_fraction: float)` (`matrix` maps RoomPlan world → detail world, 4×4)
    - `wall_points_xz(vertices, faces, classification) -> np.ndarray`: centroids of class-1 faces, as (K,2) xz
    - `floor_y(vertices, faces, classification) -> float`: median y of class-2 face centroids
    - `solve_alignment(walls, mesh_wall_xz, roomplan_floor_y, mesh_floor_y) -> Alignment`
    - `align_scan(scan_dir: Path) -> Alignment` (writes `alignment.json`)
    - CLI: `python tools/align.py scans/<id>`, which prints yaw in degrees, translation, rms in cm, and inlier %

Algorithm (not determined by the signatures):
1. Sample the RoomPlan wall segments in xz every 5 cm.
2. Run 2D trimmed ICP (point-to-segment, keeping the closest 80%, 30 iterations, inlier < 0.10 m). Do 24 starts at yaw 0°, 15°, …, 345°. Each start's initial translation = median(mesh points) − median(rotated samples).
3. Of the solutions whose rms is within 10% of the best, pick the one with the smallest |yaw| (wrapped to ±180°). Both passes start where the user stands, so small yaw is the likely truth. This also resolves the 180° ambiguity in symmetric rooms.
4. Translation y = mesh_floor_y − roomplan_floor_y, where roomplan_floor_y = min over walls of (center.y − height/2).

- [ ] **Step 1: Write failing tests:**
  - `test_recovers_known_transform_lshape`:
    - L-shaped room of 6 walls; mesh wall points sampled every 2 cm from 5 of the walls (one open side)
    - mesh points transformed by yaw 37°, t=(1.2, −0.3, 2.0), with Gaussian noise σ=0.01
    - expect |yaw − 37°| < 0.5°, ‖t − true‖ < 0.02, rms < 0.02
  - `test_symmetric_room_prefers_small_yaw`: a 4×5 m rectangle, true yaw 5°, t=(0.3, 0, 0.2) → recovered yaw within 0.5° of 5° (not 185°)
  - `test_floor_offset`: roomplan floor 0.0, mesh floor −1.45 → translation[1] ≈ −1.45
  - `test_too_few_walls_raises`: 1 wall → `AlignmentError` whose message contains "at least 2 walls"
  - `test_too_few_points_raises`: 150 mesh wall points → `AlignmentError` containing "wall points"
  - `test_align_scan_writes_json` (conftest fixture writes `walls.json` + a `mesh.ply` via plyfile into `tmp_path`): `alignment.json` has keys `yawDegrees`, `translation`, `matrix` (16 floats, column-major), `rmsMeters`, `inlierFraction`
- [ ] **Step 2:** `python -m venv .venv && .venv/Scripts/pip install -r tools/requirements.txt`, then `.venv/Scripts/python -m pytest tools/tests -v`. Confirm the tests FAIL (import errors).
- [ ] **Step 3: Implement `scan_io.py` and `align.py`.**
- [ ] **Step 4: Run pytest; all PASS.**
- [ ] **Step 5: Spike verdict on real data.**
  1. Run `align.py` on the uploaded gym scan. Expect rms < 0.05 m.
  2. Do one more scan with **Reuse RoomPlan session** on, and run `align.py` on it.
  3. If the reuse scan's alignment is ~identity (|yaw| < 1°, ‖t‖ < 0.03), record "session reuse works on iOS 16.4.1" in `docs/superpowers/specs/2026-10-24-iscan-design.md` under Capture app. Otherwise record that registration is required.
  4. Report both rms values to the user.
- [ ] **Step 6: Commit** `feat(tools): RoomPlan-to-mesh alignment with spike results`.
