import json
import sys
from pathlib import Path

import numpy as np
import pytest
from plyfile import PlyData, PlyElement

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

WALL, FLOOR = 1, 2


def yaw_matrix(degrees: float) -> np.ndarray:
    """Right-handed rotation about +Y (counterclockwise seen from above)."""
    t = np.radians(degrees)
    c, s = np.cos(t), np.sin(t)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def wall_record(p0, p1, height=2.4, floor=0.0) -> dict:
    """A walls.json wall from xz endpoints, in the RoomSummary format the app writes."""
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    d = p1 - p0
    width = float(np.linalg.norm(d))
    x = np.array([d[0], 0.0, d[1]]) / width
    z = np.cross(x, [0.0, 1.0, 0.0])
    center = [(p0[0] + p1[0]) / 2, floor + height / 2, (p0[1] + p1[1]) / 2]
    cols = [[*x, 0.0], [0.0, 1.0, 0.0, 0.0], [*z, 0.0], [*center, 1.0]]
    return {
        "kind": "wall",
        "category": "wall",
        "transform": [float(v) for col in cols for v in col],
        "dimensions": [width, height, 0.0],
        "confidence": "high",
    }


def sample_walls(segments, spacing=0.02, height=2.4) -> np.ndarray:
    """3D points covering each wall surface, spaced `spacing` apart along the wall and 0.3 m apart vertically."""
    pts = []
    for p0, p1 in segments:
        p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
        n = max(2, int(np.linalg.norm(p1 - p0) / spacing))
        for t in np.linspace(0, 1, n):
            xz = p0 + t * (p1 - p0)
            for y in np.arange(0.15, height, 0.3):
                pts.append([xz[0], y, xz[1]])
    return np.array(pts)


def write_mesh(path: Path, wall_points: np.ndarray, floor_y: float) -> None:
    """A PLY in the app's format: one tiny triangle per wall point (class wall) plus a floor quad."""
    verts, faces, cls = [], [], []
    for p in wall_points:
        i = len(verts)
        verts += [p, p + [0.005, 0, 0], p + [0, 0.005, 0]]
        faces.append([i, i + 1, i + 2])
        cls.append(WALL)
    i = len(verts)
    verts += [[-20, floor_y, -20], [20, floor_y, -20], [20, floor_y, 20], [-20, floor_y, 20]]
    faces += [[i, i + 1, i + 2], [i, i + 2, i + 3]]
    cls += [FLOOR, FLOOR]
    v = np.array([tuple(p) for p in verts], dtype=[("x", "f4"), ("y", "f4"), ("z", "f4")])
    f = np.array(
        [(tuple(fc), c) for fc, c in zip(faces, cls)],
        dtype=[("vertex_indices", "u4", (3,)), ("classification", "u1")],
    )
    face_el = PlyElement.describe(f, "face", len_types={"vertex_indices": "u1"}, val_types={"vertex_indices": "u4"})
    PlyData([PlyElement.describe(v, "vertex"), face_el], text=False, byte_order="<").write(str(path))


L_ROOM = [((0, 0), (6, 0)), ((6, 0), (6, 3)), ((6, 3), (3, 3)), ((3, 3), (3, 5)), ((3, 5), (0, 5)), ((0, 5), (0, 0))]


@pytest.fixture
def scan_dir(tmp_path: Path) -> Path:
    """A minimal scan bundle: L-shaped room, mesh rotated 37 degrees and shifted, one wall unscanned."""
    rot, t = yaw_matrix(37), np.array([1.2, -0.3, 2.0])
    (tmp_path / "walls.json").write_text(
        json.dumps({"schemaVersion": 1, "walls": [wall_record(a, b) for a, b in L_ROOM],
                    "doors": [], "windows": [], "openings": [], "objects": []})
    )
    pts = sample_walls(L_ROOM[:5], spacing=0.05) @ rot.T + t
    write_mesh(tmp_path / "mesh.ply", pts, floor_y=-0.3)
    return tmp_path
