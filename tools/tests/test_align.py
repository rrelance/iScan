import json

import numpy as np
import pytest

from align import AlignmentError, align_scan, solve_alignment
from conftest import L_ROOM, sample_walls, wall_record, yaw_matrix
from scan_io import Wall


def walls_from(segments, floor=0.0):
    out = []
    for a, b in segments:
        r = wall_record(a, b, floor=floor)
        m = np.array(r["transform"]).reshape(4, 4).T
        out.append(Wall(center=m[:3, 3], x_axis=m[:3, 0], width=r["dimensions"][0], height=r["dimensions"][1]))
    return out


def mesh_xz(segments, yaw, t, noise=0.01, seed=0):
    pts = sample_walls(segments) @ yaw_matrix(yaw).T + np.asarray(t)
    pts += np.random.default_rng(seed).normal(0, noise, pts.shape)
    return pts[:, [0, 2]]


def yaw_error(a, b):
    return abs((a - b + 180) % 360 - 180)


def test_recovers_known_transform_lshape():
    t = np.array([1.2, -0.3, 2.0])
    result = solve_alignment(walls_from(L_ROOM), mesh_xz(L_ROOM[:5], 37, t), 0.0, -0.3)
    assert yaw_error(np.degrees(result.yaw_rad), 37) < 0.5
    assert np.linalg.norm(result.translation - t) < 0.02
    assert result.rms < 0.02
    corner = np.array([6.0, 0.0, 3.0, 1.0])
    expected = yaw_matrix(37) @ corner[:3] + t
    assert np.allclose((result.matrix @ corner)[:3], expected, atol=0.03)


def test_symmetric_room_prefers_small_yaw():
    rect = [((0, 0), (4, 0)), ((4, 0), (4, 5)), ((4, 5), (0, 5)), ((0, 5), (0, 0))]
    result = solve_alignment(walls_from(rect), mesh_xz(rect, 5, [0.3, 0, 0.2]), 0.0, 0.0)
    assert yaw_error(np.degrees(result.yaw_rad), 5) < 0.5


def test_floor_offset():
    result = solve_alignment(walls_from(L_ROOM), mesh_xz(L_ROOM, 0, [0, -1.45, 0]), 0.0, -1.45)
    assert result.translation[1] == pytest.approx(-1.45, abs=1e-6)


def test_too_few_walls_raises():
    with pytest.raises(AlignmentError, match="at least 2 walls"):
        solve_alignment(walls_from(L_ROOM[:1]), mesh_xz(L_ROOM, 0, [0, 0, 0]), 0.0, 0.0)


def test_too_few_points_raises():
    pts = mesh_xz(L_ROOM, 0, [0, 0, 0])[:150]
    with pytest.raises(AlignmentError, match="wall points"):
        solve_alignment(walls_from(L_ROOM), pts, 0.0, 0.0)


def test_align_scan_writes_json(scan_dir):
    result = align_scan(scan_dir)
    data = json.loads((scan_dir / "alignment.json").read_text())
    assert set(data) == {"yawDegrees", "translation", "matrix", "rmsMeters", "inlierFraction"}
    assert len(data["matrix"]) == 16 and len(data["translation"]) == 3
    assert data["matrix"][12:15] == pytest.approx(list(result.translation))
    assert yaw_error(data["yawDegrees"], 37) < 0.5
