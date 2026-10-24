# iScan: LiDAR gym capture + Claude-assisted layout planner

## Context

The user wants to digitize their basement home gym with their iPhone's LiDAR + camera, hand the data to Claude to model, then rearrange the equipment virtually. Motivation: the space feels cramped (they can't pinpoint why) and they want a digital twin to experiment with.

Browser-only capture is impossible: iOS Safari exposes no LiDAR/depth and no WebXR (verified Oct 2026). The phone is jailbroken with TrollStore, so a native app can be sideloaded with no Apple Developer account. The user is on Windows, so the app is compiled on GitHub Actions macOS runners.

**Device:** iPhone 12 Pro Max, iOS 16.4.1, TrollStore (LiDAR, RoomPlan v1, ARKit 6).
**PC:** Windows 11, Node 24, Python 3.13, git; no `gh` CLI. Repo dir `C:\Users\XI\GIT\iScan` is empty, not yet a git repo.

## The gym (from the user)
- Part of an **open basement**: walls on some sides, open on others.
- **Low beams/ducts** and **support posts** constrain placement.
- Equipment: rack/barbell station, benches + free weights, cardio machines, cable/selectorized machines.
- **Movable items = equipment + storage units** (dumbbell racks, plate trees). Loose plates, mats, and accessories are excluded.

## Decisions (user's)
- Native iOS capture app, built via GitHub Actions in a **public** GitHub repo (the user has an account), installed via TrollStore.
- Planner is a browser app on the PC: split view, draggable 2D top-down plan + live 3D view, multiple saved layouts.
- Extras: **Claude-suggested layouts** and **AR preview on phone**.
- Claude works **through Claude Code** (no API key): scans land in the project folder; Claude reads them and writes model/layout files that the planner picks up live.

## Calls I made (user can override)
- Each item is a measured, labeled box that drives layout and collisions. The cropped LiDAR mesh is used as the item's look in 3D. (ARKit mesh is too coarse for thin rack uprights to be the source of truth.)
- No warnings/"space audit" UI. Clearance rules live in data and drive Claude's suggestions. The planner only tints an item while dragging if it overlaps something or doesn't fit under a beam.
- Phone→PC transfer: Wi-Fi upload to the PC server (Bonjour + manual IP), with share-sheet zip export as fallback.
- Stack: SwiftUI + RoomPlan + ARKit + RealityKit (iOS); XcodeGen; Node/Fastify server; Vite/React/TS + react-three-fiber planner; Python (numpy/trimesh/open3d) processing tools that Claude runs.

## Non-goals
Web capture, multi-room stitching, photoreal textures, cloud hosting, buying catalog, warnings UI, outlet planning, flooring zones.

## Architecture

```
iPhone (iScan) --Wi-Fi upload--> PC server (Node :8787) --> scans/<id>/
                                                              |
                     Claude Code: tools/process_scan.py + photo review
                                                              v
                     model/gym.json, model/items/*.glb, layouts/*.json
                                                              |
   browser planner (2D+3D) <--SSE live reload-- server --> iPhone AR preview
```

### Repo layout (new)
- `ios/`: SwiftUI app, `project.yml` (XcodeGen), `iScan.entitlements`
- `.github/workflows/ios.yml`: builds the ldid-signed `iScan.ipa` and publishes it as a GitHub Release asset
- `server/`: Fastify, covering upload, model/layout API, SSE, Bonjour, and serving the planner
- `planner/`: Vite + React + TS + @react-three/fiber/drei; 2D plan in SVG
- `tools/`: `process_scan.py`, `align.py`, `export_items.py`, `check_layout.py`, `clearances.json`
- `scans/` (gitignored), `model/`, `layouts/`
- `CLAUDE.md`: modeling and layout-suggestion workflow for future sessions

### 1. Capture app (iOS 16.4)
Two passes, run back to back:
1. **Room pass:** `RoomCaptureView` → `CapturedRoom` → `room.json` (Codable) + `room.usdz`. This gives walls, doors, windows, and any objects it recognizes. In an open basement it only captures the walls it sees, which is fine.
2. **Detail pass:** an `ARWorldTrackingConfiguration` session with `sceneReconstruction = .meshWithClassification`, `frameSemantics = .sceneDepth`, and the high-res-capable video format.
   - A live mesh overlay shows coverage. The user is prompted to sweep the ceiling as well, to capture beams and ducts.
   - Auto-capture `captureHighResolutionFrame` every ~0.5 m / ~20° of movement when tracking is normal, plus a manual shutter. Each photo stores the depth/confidence of the nearest regular ARFrame, with intrinsics scaled to the photo.
   - Save an `ARWorldMap` at the end. **The detail session's world frame is the master frame.**
   - **Alignment:** RoomPlan walls are registered to the detail session's mesh in processing (`align.py`: match wall-classified mesh planes to RoomPlan wall planes and floor height). It solves yaw + translation, with the residual reported.
   - **Spike option:** test whether re-running RoomPlan's own `arSession` keeps the origin on iOS 16 (that API is officially iOS 17+). If it does, registration becomes a sanity check only.
   - **Spike result (2026-10-24, iPhone 12 Pro Max, iOS 16.4.1): session reuse does NOT keep the origin.** The reuse scan `20261024-180549` still needed yaw −53.2°, t = (0.38, 0.09, −0.26) m. **Registration is required.** It works well: the full scan `20261024-174746` aligned at 4.5 cm rms with 79% inliers, and the reuse scan at 4.3 cm / 83%. The reuse toggle stays off by default.

**Bundle** `scans/<yyyyMMdd-HHmmss>/`:
- `manifest.json` (schema version, device, iOS, units = meters)
- `room.json`, `room.usdz`
- `mesh.ply` (world-space, per-face classification, ceiling faces kept)
- `frames/NNNN.jpg` with `NNNN.json` (intrinsics, transform, resolution, timestamp), `NNNN_depth.png` (16-bit mm), and `NNNN_conf.png`
- `worldmap.arworldmap`

**Upload:** Bonjour `_iscan._tcp` or a manual IP. Zip, then POST `/api/scans` with progress and retry. Share-sheet export as fallback.
**Info.plist:** camera and local-network usage strings, `NSBonjourServices`, ATS `NSAllowsLocalNetworking`.
**Screens:** Home (scans, New Scan, AR Preview, Settings) → Room pass → Detail pass → Review/Upload.

### 2. Build pipeline
GitHub Actions `macos-latest`:
1. `brew install xcodegen ldid`
2. `xcodegen`
3. `xcodebuild -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO`
4. `ldid -S<entitlements>` on the **app binary** `Payload/iScan.app/iScan`
5. Zip as `iScan.ipa`
6. Publish as a **GitHub Release asset** (on tag push + manual dispatch), so the phone downloads it in Safari without logging in and opens it in TrollStore.

The repo is public, so builds are free.

### 3. PC server (`server/`)
Fastify on `0.0.0.0:8787`:
- `POST /api/scans` (stream unzip)
- `GET /api/model` + item GLBs
- `GET/PUT/POST/DELETE /api/layouts[/:id]`
- `GET /api/events` (SSE, chokidar on `model/` + `layouts/`)
- `GET /api/ar/:layoutId`
- Serves the planner build.

On startup it prints the LAN URL and the Windows firewall commands (TCP 8787 + UDP 5353 for mDNS). If Bonjour conflicts with Windows' own mDNS, it falls back to manual IP.

### 4. Modeling (Claude's job, tooling in `tools/`)
`process_scan.py <scan>`:
1. Run `align.py`.
2. Build a **ceiling height map** (5 cm grid) from ceiling-classified and overhead faces, then extract **low zones** (beams/ducts) as polygons with clearance height.
3. Drop floor/wall/ceiling faces and cluster the remainder (connected components → DBSCAN).
4. For each cluster, compute an oriented bounding box, footprint, and height.
5. Pick the best photos by projecting each cluster into the frames.
6. Write `model/candidates.json`, a top-down render (mesh + walls + ceiling map), and per-cluster photo crops.

Claude then reviews the crops and renders, merges or splits clusters, and labels each one as an item (equipment/storage), a **post** (fixed obstacle), or ignore (loose clutter). It assigns clearance from `clearances.json`, drafts the **boundary** (scanned walls plus straight open edges inferred from the mesh extent), and writes `model/gym.json`. `export_items.py` writes the cropped meshes re-centered to `model/items/<id>.glb`. The user fixes labels and the boundary in the planner.

`gym.json` (meters, +Y up, origin at a boundary corner):
- `room.boundary`: polygon whose edges are each tagged `wall` | `open`
- `room.ceilingHeight`: nominal
- `room.overhead[]`: `{polygon, clearance}` for beams and ducts
- `room.posts[]`: `{footprint}`
- `room.doors[]`, `room.windows[]`
- `items[]`: `{id, name, type, fixed, size{w,d,h}, footprint[], mesh, pose{x,z,rotY}, clearance{front,back,left,right}, needsOverhead}`
  - `needsOverhead` = the height the item needs, such as a rack's height or pull-up/overhead-press clearance
- `scanId`, `alignment` (detail-session world → gym frame, used by AR)

Layout file `layouts/<id>.json`: `{id, name, author: "user"|"claude", basedOn, rationale, poses{itemId:{x,z,rotY}}}`. `current` = the as-scanned layout.

`clearances.json` holds per-type working zones from published guidance (e.g. ASTM F2115 treadmill ~2 m behind / 0.5 m sides; rack bar-end + walk-out zones; ~0.9 m walkways).

### 5. Planner (`planner/`)
- **Left, 2D plan (SVG):**
  - Boundary: solid walls, dashed open edges. Edit mode lets the user drag vertices and toggle wall/open.
  - Posts drawn solid. Overhead low zones hatched with their clearance labelled.
  - Doors with swing arcs.
  - Items as labeled footprints. Drag to move; rotate with a handle or `R` (15° snap, Shift = free); snap to walls.
  - While dragging, an item is tinted if it overlaps another item, a post, or the boundary, or if its `needsOverhead` exceeds the local clearance.
  - Side panel: name, type, size, distances to walls; editable label and type.
- **Right, 3D (r3f):**
  - Walls extruded with a cutaway, posts, and beams/ducts as boxes at their real height.
  - Item meshes, with the box as fallback.
  - Orbit, top/iso presets, selection synced with the 2D plan.
- **Top bar:**
  - Layout tabs (Current, user layouts, Claude options with a badge), with duplicate/rename/delete.
  - Undo/redo and autosave.
  - A rationale panel for Claude options.
- **SSE live reload**, so layouts Claude writes appear instantly.

### 6. Claude-suggested layouts
Documented in `CLAUDE.md`. When the user asks "suggest N layouts", Claude reads `gym.json` + `clearances.json`. It writes options that respect:
- the boundary and posts
- door swings
- overhead clearance for tall or overhead stations
- clearance zones and walkways

Each option goes to `layouts/claude-<slug>.json` with its rationale. `tools/check_layout.py` must pass before a file is written. It checks for overlaps, boundary violations, posts, overhead clearance, and doors.

### 7. AR preview (iOS)
1. Pick a layout from the server.
2. Load the `ARWorldMap` via `initialWorldMap` and show relocalization status.
3. Map the poses through `gym.json.alignment`.
4. For each moved item, RealityKit shows a red outline at the old pose and a translucent green mesh/box at the new pose.
5. Unmoved items are hidden, with a toggle to show all.

## Milestones (each ends with a user-visible check)
0. **Pipeline proof:** `git init`, public GitHub repo, a hello-world SwiftUI app → CI Release asset → the user installs it via TrollStore. (Highest risk, done first.)
1. **Capture spike:** both passes, export raw data, `align.py` residual check. Also try the RoomPlan session-continuation option.
2. Full capture app + bundle + Wi-Fi upload into `scans/`.
3. `process_scan.py` (ceiling map, clustering, crops) + first real model of the gym → the user reviews labels and the boundary.
4. Planner: 2D + 3D + boundary editing + layouts + live reload.
5. Claude layout suggestions + `check_layout.py` + `CLAUDE.md`.
6. AR preview.

## Verification
- **CI:** the Release has `iScan.ipa`; it installs via TrollStore and launches.
- **Capture:** a real gym scan has the manifest, frames, and depth; `align.py` residual under 5 cm; a top-down overlay of RoomPlan walls on the mesh looks right.
- **Server:** the phone uploads over Wi-Fi and the files land in `scans/`. vitest covers the layout API and zip handling.
- **Modeling:** item box sizes vs 2–3 tape-measured items (±5 cm target); 1–2 beam heights tape-measured vs the ceiling map (±5 cm).
- **Planner:** driven in Chrome (claude-in-chrome) to check drag/rotate/save, boundary editing, reload persistence, and that a layout file written on disk appears live. vitest covers geometry helpers (snap, polygon overlap, rotation, overhead lookup).
- **Layouts:** `check_layout.py` passes for every Claude option, with unit tests for its rules.
- **AR:** relocalize in the gym; ghost items sit on the floor at the expected spots (spot-check against the plan with a tape).
