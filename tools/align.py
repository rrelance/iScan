"""Register the RoomPlan pass to the ARKit detail pass.

The two passes run as separate ARKit sessions, so their world origins differ. Both are
gravity-aligned, which leaves a yaw about +Y plus a translation. The floor fixes the
vertical offset; the yaw and horizontal offset come from 2D ICP between the RoomPlan wall
segments and the wall-classified mesh faces, seen from above (xz plane).

Usage: python tools/align.py scans/<id>
"""

import json
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from scan_io import Wall, load_mesh, load_walls

WALL, FLOOR = 1, 2
MIN_WALL_POINTS = 200
MAX_POINTS = 4000
INLIER_DISTANCE = 0.10
KEEP_FRACTION = 0.8
ITERATIONS = 30
REFINE_ITERATIONS = 150
REFINE_CANDIDATES = 6
AMBIGUOUS_YAW_DEG = 10
MIN_WALL_SPREAD_DEG = 20
MIN_INLIER_FRACTION = 0.5
START_YAWS_DEG = range(0, 360, 15)


class AlignmentError(Exception):
    pass


@dataclass
class Alignment:
    yaw_rad: float
    translation: np.ndarray
    matrix: np.ndarray  # 4x4, maps RoomPlan world -> detail world
    rms: float
    inlier_fraction: float


def wall_points_xz(vertices: np.ndarray, faces: np.ndarray, classification: np.ndarray) -> np.ndarray:
    centroids = vertices[faces[classification == WALL]].mean(axis=1)
    return centroids[:, [0, 2]]


def floor_y(vertices: np.ndarray, faces: np.ndarray, classification: np.ndarray) -> float:
    floor = faces[classification == FLOOR]
    if len(floor) == 0:
        raise AlignmentError("mesh has no floor faces; rescan with the floor in view")
    return float(np.median(vertices[floor].mean(axis=1)[:, 1]))


def _rot2(phi: float) -> np.ndarray:
    """Counterclockwise rotation in (x, z) coordinates. A yaw of theta about +Y is phi = -theta here."""
    c, s = np.cos(phi), np.sin(phi)
    return np.array([[c, -s], [s, c]])


def _closest_on_segments(p: np.ndarray, a: np.ndarray, b: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """For each point, the closest point on any segment a[i]-b[i], and its distance."""
    ab = b - a
    t = np.einsum("nsk,sk->ns", p[:, None, :] - a[None], ab) / np.einsum("sk,sk->s", ab, ab)
    q = a[None] + np.clip(t, 0, 1)[..., None] * ab[None]
    d = np.linalg.norm(p[:, None, :] - q, axis=2)
    idx = d.argmin(axis=1)
    rows = np.arange(len(p))
    return q[rows, idx], d[rows, idx]


def _icp(a: np.ndarray, b: np.ndarray, pts: np.ndarray, phi: float, t: np.ndarray,
         iterations: int = ITERATIONS) -> tuple[float, np.ndarray, float]:
    """Trimmed point-to-segment ICP moving the segments onto `pts`. Returns (phi, t, rms of kept pairs)."""
    keep = max(3, int(len(pts) * KEEP_FRACTION))
    rms = np.inf
    for _ in range(iterations):
        r = _rot2(phi)
        q, d = _closest_on_segments(pts, a @ r.T + t, b @ r.T + t)
        order = np.argsort(d)[:keep]
        q, p = q[order], pts[order]
        rms = float(np.sqrt(np.mean(d[order] ** 2)))
        qc, pc = q.mean(axis=0), p.mean(axis=0)
        h = (q - qc).T @ (p - pc)
        dphi = np.arctan2(h[0, 1] - h[1, 0], h[0, 0] + h[1, 1])
        dr = _rot2(dphi)
        phi += dphi
        t = dr @ (t - qc) + pc
    return phi, t, rms


def _wrap(angle: float) -> float:
    return (angle + np.pi) % (2 * np.pi) - np.pi


def solve_alignment(walls: list[Wall], mesh_wall_xz: np.ndarray, roomplan_floor_y: float,
                    mesh_floor_y: float) -> Alignment:
    if len(walls) < 2:
        raise AlignmentError(f"RoomPlan found {len(walls)} wall(s); alignment needs at least 2 walls")
    if len(mesh_wall_xz) < MIN_WALL_POINTS:
        raise AlignmentError(f"only {len(mesh_wall_xz)} wall points in the mesh (need {MIN_WALL_POINTS}); "
                             "scan more of the walls during the detail pass")

    directions = [np.arctan2(w.x_axis[2], w.x_axis[0]) % np.pi for w in walls]
    spread = max(min(abs(p - q), np.pi - abs(p - q)) for p in directions for q in directions)
    if np.degrees(spread) < MIN_WALL_SPREAD_DEG:
        raise AlignmentError("all RoomPlan walls are parallel, so the position along them is undetermined; "
                             "alignment needs walls in at least two directions")

    pts = mesh_wall_xz
    if len(pts) > MAX_POINTS:
        pts = pts[np.random.default_rng(0).choice(len(pts), MAX_POINTS, replace=False)]
    ends = [w.endpoints_xz() for w in walls]
    a = np.array([e[0] for e in ends])
    b = np.array([e[1] for e in ends])
    samples = np.vstack([np.linspace(s, e, max(2, int(np.linalg.norm(e - s) / 0.05))) for s, e in zip(a, b)])

    solutions = []
    for deg in START_YAWS_DEG:
        phi0 = np.radians(deg)
        t0 = np.median(pts, axis=0) - np.median(samples @ _rot2(phi0).T, axis=0)
        solutions.append(_icp(a, b, pts, phi0, t0))

    # Point-to-segment ICP slides slowly along walls, so only the promising coarse
    # solutions get the long refinement.
    solutions.sort(key=lambda s: s[2])
    refined = [_icp(a, b, pts, phi, t, REFINE_ITERATIONS) for phi, t, _ in solutions[:REFINE_CANDIDATES]]

    # A symmetric room fits equally well at several yaws, and the two passes can start facing
    # any direction, so there is no safe way to pick one: refuse instead of guessing.
    best = min(s[2] for s in refined)
    close = [s for s in refined if s[2] <= max(best * 1.1, best + 0.005)]
    phi, t2, _ = min(close, key=lambda s: s[2])

    _, d = _closest_on_segments(mesh_wall_xz, a @ _rot2(phi).T + t2, b @ _rot2(phi).T + t2)
    inliers = d < INLIER_DISTANCE
    if inliers.mean() < MIN_INLIER_FRACTION:
        raise AlignmentError(f"only {inliers.mean() * 100:.0f}% of mesh wall points match the RoomPlan walls "
                             f"(need {MIN_INLIER_FRACTION * 100:.0f}%); the two passes may not show the same room")
    rivals = [s for s in close if abs(np.degrees(_wrap(s[0] - phi))) > AMBIGUOUS_YAW_DEG]
    if rivals:
        raise AlignmentError(
            f"ambiguous: the walls fit equally well at yaw {np.degrees(_wrap(-phi)):.0f} and "
            f"{np.degrees(_wrap(-rivals[0][0])):.0f} degrees (symmetric room); scan more asymmetric features")
    # Measured over inliers only; read together with inlier_fraction.
    rms = float(np.sqrt(np.mean(d[inliers] ** 2)))

    yaw = _wrap(-phi)
    c, s = np.cos(yaw), np.sin(yaw)
    translation = np.array([t2[0], mesh_floor_y - roomplan_floor_y, t2[1]])
    matrix = np.eye(4)
    matrix[:3, :3] = [[c, 0, s], [0, 1, 0], [-s, 0, c]]
    matrix[:3, 3] = translation
    return Alignment(yaw_rad=float(yaw), translation=translation, matrix=matrix, rms=rms,
                     inlier_fraction=float(inliers.mean()))


def align_scan(scan_dir: Path) -> Alignment:
    scan_dir = Path(scan_dir)
    if not (scan_dir / "walls.json").exists():
        raise AlignmentError("no walls.json: the room pass was skipped, and alignment needs the RoomPlan walls")
    if not (scan_dir / "mesh.ply").exists():
        raise AlignmentError("no mesh.ply: the detail pass didn't finish")
    walls = load_walls(scan_dir / "walls.json")
    vertices, faces, cls = load_mesh(scan_dir / "mesh.ply")
    roomplan_floor = min((w.center[1] - w.height / 2 for w in walls), default=0.0)
    result = solve_alignment(walls, wall_points_xz(vertices, faces, cls), roomplan_floor,
                             floor_y(vertices, faces, cls))
    (scan_dir / "alignment.json").write_text(json.dumps({
        "yawDegrees": float(np.degrees(result.yaw_rad)),
        "translation": [float(v) for v in result.translation],
        "matrix": [float(v) for v in result.matrix.T.flatten()],
        "rmsMeters": result.rms,
        "inlierFraction": result.inlier_fraction,
    }, indent=2))
    return result


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__.strip().splitlines()[-1])
        return 2
    try:
        r = align_scan(Path(argv[1]))
    except AlignmentError as e:
        print(f"Alignment failed: {e}")
        return 1
    print(f"yaw {np.degrees(r.yaw_rad):.2f} deg, translation {np.round(r.translation, 3).tolist()} m, "
          f"rms {r.rms * 100:.1f} cm, inliers {r.inlier_fraction * 100:.0f}%")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
