from __future__ import annotations

from dataclasses import dataclass
from math import hypot
from typing import Iterable


@dataclass(frozen=True)
class Point:
    x: float
    y: float


def point_in_polygon(point: Point, polygon: Iterable[Point]) -> bool:
    """Ray-casting point-in-polygon test for simple floor-plan polygons."""
    pts = list(polygon)
    if len(pts) < 3:
        return False
    inside = False
    j = len(pts) - 1
    for i, pi in enumerate(pts):
        pj = pts[j]
        crosses = ((pi.y > point.y) != (pj.y > point.y)) and (
            point.x < (pj.x - pi.x) * (point.y - pi.y) / ((pj.y - pi.y) or 1e-12) + pi.x
        )
        if crosses:
            inside = not inside
        j = i
    return inside


def nearest_desk(point: Point, desks: list[dict], zone_id: str | None) -> tuple[dict | None, float | None]:
    candidates = [d for d in desks if zone_id is None or d.get("zone_id") == zone_id]
    if not candidates:
        return None, None
    ranked = sorted((hypot(point.x - d["x"], point.y - d["y"]), d) for d in candidates)
    distance, desk = ranked[0]
    radius = float(desk.get("radius", 4.0))
    return (desk, distance) if distance <= radius else (None, distance)


def locate(point: Point, layout: dict) -> dict:
    zone = None
    for candidate in layout.get("zones", []):
        polygon = [Point(**p) for p in candidate.get("polygon", [])]
        if point_in_polygon(point, polygon):
            zone = candidate
            break
    desk, distance = nearest_desk(point, layout.get("desks", []), zone["id"] if zone else None)
    return {
        "zone_id": zone["id"] if zone else None,
        "zone_name": zone["name"] if zone else None,
        "desk_id": desk["id"] if desk else None,
        "desk_name": desk["name"] if desk else None,
        "desk_distance": round(distance, 2) if distance is not None else None,
    }
