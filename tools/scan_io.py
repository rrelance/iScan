"""Readers for the files in an iScan scan bundle."""

import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from plyfile import PlyData


@dataclass
class Wall:
    """A RoomPlan wall: a vertical rectangle centered at `center`, spanning `width` along `x_axis`."""

    center: np.ndarray
    x_axis: np.ndarray
    width: float
    height: float

    def endpoints_xz(self) -> tuple[np.ndarray, np.ndarray]:
        half = self.x_axis * self.width / 2
        return (self.center - half)[[0, 2]], (self.center + half)[[0, 2]]


def load_walls(path) -> list[Wall]:
    """Walls from `walls.json` (RoomSummary). Transforms are 16 floats, column-major."""
    summary = json.loads(Path(path).read_text())
    walls = []
    for w in summary.get("walls", []):
        m = np.asarray(w["transform"], dtype=float).reshape(4, 4).T
        walls.append(Wall(center=m[:3, 3], x_axis=m[:3, 0], width=float(w["dimensions"][0]),
                          height=float(w["dimensions"][1])))
    return walls


def load_mesh(path) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """(vertices (N,3), faces (M,3), per-face ARKit classification (M,)) from `mesh.ply`."""
    ply = PlyData.read(str(path))
    v = ply["vertex"]
    vertices = np.column_stack([v["x"], v["y"], v["z"]]).astype(float)
    f = ply["face"]
    if f.count == 0:
        return vertices, np.zeros((0, 3), dtype=np.int64), np.zeros(0, dtype=np.uint8)
    faces = np.vstack(f["vertex_indices"]).astype(np.int64)
    return vertices, faces, np.asarray(f["classification"], dtype=np.uint8)
