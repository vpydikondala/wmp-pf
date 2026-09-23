from __future__ import annotations

from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import UUID, uuid4

from fastapi import FastAPI, HTTPException, Response, status
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from .store import apply_migrations, connection

STATIC_DIR = Path(__file__).parent / "static"


@asynccontextmanager
async def lifespan(_: FastAPI):
    apply_migrations()
    yield


app = FastAPI(title="Workplace Management", version="2.0.0", lifespan=lifespan)
app.mount("/management/static", StaticFiles(directory=STATIC_DIR), name="static")


class BuildingIn(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    code: str | None = Field(default=None, max_length=100)
    address: str | None = None
    timezone: str = "Europe/London"
    active: bool = True


class FloorIn(BaseModel):
    building_id: UUID
    name: str = Field(min_length=1, max_length=200)
    floor_number: int | None = None
    map_width: float = Field(default=100, gt=0)
    map_height: float = Field(default=100, gt=0)
    floor_plan_s3_key: str | None = None
    active: bool = True


class ZoneIn(BaseModel):
    floor_id: UUID
    name: str = Field(min_length=1, max_length=200)
    zone_type: str | None = None
    polygon: list[dict[str, float]] = Field(default_factory=list)
    capacity: int | None = Field(default=None, ge=0)
    active: bool = True


class AccessPointIn(BaseModel):
    floor_id: UUID | None = None
    zone_id: UUID | None = None
    serial: str = Field(min_length=1, max_length=128)
    name: str | None = None
    mac_address: str | None = None
    x: float | None = None
    y: float | None = None
    active: bool = True


class DeskIn(BaseModel):
    floor_id: UUID
    zone_id: UUID | None = None
    name: str = Field(min_length=1, max_length=200)
    x: float
    y: float
    active: bool = True


def _rows(sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    with connection() as conn:
        return list(conn.execute(sql, params).fetchall())


def _one(sql: str, params: tuple[Any, ...] = ()) -> dict[str, Any]:
    with connection() as conn:
        row = conn.execute(sql, params).fetchone()
    if row is None:
        raise HTTPException(404, "record not found")
    return dict(row)


def _delete(table: str, item_id: UUID) -> Response:
    allowed = {"buildings", "floors", "zones", "access_points", "desks"}
    if table not in allowed:
        raise HTTPException(400, "invalid resource")
    with connection() as conn:
        row = conn.execute(f"DELETE FROM {table} WHERE id=%s RETURNING id", (item_id,)).fetchone()
    if row is None:
        raise HTTPException(404, "record not found")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.get("/")
@app.get("/management")
@app.get("/management/")
def index():
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/health")
def health():
    try:
        with connection() as conn:
            conn.execute("SELECT 1").fetchone()
        return {"status": "ok", "service": "management", "database": "ok"}
    except Exception as exc:
        raise HTTPException(503, f"database unavailable: {type(exc).__name__}") from exc


@app.get("/api/v1/management/buildings")
def list_buildings():
    return _rows("SELECT * FROM buildings ORDER BY name")


@app.post("/api/v1/management/buildings", status_code=201)
def create_building(item: BuildingIn):
    item_id = uuid4()
    return _one("""INSERT INTO buildings(id,name,code,address,timezone,active) VALUES(%s,%s,%s,%s,%s,%s) RETURNING *""",
                (item_id,item.name,item.code,item.address,item.timezone,item.active))


@app.put("/api/v1/management/buildings/{item_id}")
def update_building(item_id: UUID, item: BuildingIn):
    return _one("""UPDATE buildings SET name=%s,code=%s,address=%s,timezone=%s,active=%s,updated_at=NOW() WHERE id=%s RETURNING *""",
                (item.name,item.code,item.address,item.timezone,item.active,item_id))


@app.delete("/api/v1/management/buildings/{item_id}", status_code=204)
def delete_building(item_id: UUID): return _delete("buildings", item_id)


@app.get("/api/v1/management/floors")
def list_floors(building_id: UUID | None = None):
    return _rows("SELECT * FROM floors WHERE (%s::uuid IS NULL OR building_id=%s) ORDER BY floor_number NULLS LAST,name", (building_id, building_id))


@app.post("/api/v1/management/floors", status_code=201)
def create_floor(item: FloorIn):
    return _one("""INSERT INTO floors(id,building_id,name,floor_number,map_width,map_height,floor_plan_s3_key,active) VALUES(%s,%s,%s,%s,%s,%s,%s,%s) RETURNING *""",
                (uuid4(),item.building_id,item.name,item.floor_number,item.map_width,item.map_height,item.floor_plan_s3_key,item.active))


@app.put("/api/v1/management/floors/{item_id}")
def update_floor(item_id: UUID, item: FloorIn):
    return _one("""UPDATE floors SET building_id=%s,name=%s,floor_number=%s,map_width=%s,map_height=%s,floor_plan_s3_key=%s,active=%s,updated_at=NOW() WHERE id=%s RETURNING *""",
                (item.building_id,item.name,item.floor_number,item.map_width,item.map_height,item.floor_plan_s3_key,item.active,item_id))


@app.delete("/api/v1/management/floors/{item_id}", status_code=204)
def delete_floor(item_id: UUID): return _delete("floors", item_id)


@app.get("/api/v1/management/zones")
def list_zones(floor_id: UUID | None = None):
    return _rows("SELECT * FROM zones WHERE (%s::uuid IS NULL OR floor_id=%s) ORDER BY name", (floor_id, floor_id))


@app.post("/api/v1/management/zones", status_code=201)
def create_zone(item: ZoneIn):
    import json
    return _one("""INSERT INTO zones(id,floor_id,name,zone_type,polygon,capacity,active) VALUES(%s,%s,%s,%s,%s::jsonb,%s,%s) RETURNING *""",
                (uuid4(),item.floor_id,item.name,item.zone_type,json.dumps(item.polygon),item.capacity,item.active))


@app.put("/api/v1/management/zones/{item_id}")
def update_zone(item_id: UUID, item: ZoneIn):
    import json
    return _one("""UPDATE zones SET floor_id=%s,name=%s,zone_type=%s,polygon=%s::jsonb,capacity=%s,active=%s,updated_at=NOW() WHERE id=%s RETURNING *""",
                (item.floor_id,item.name,item.zone_type,json.dumps(item.polygon),item.capacity,item.active,item_id))


@app.delete("/api/v1/management/zones/{item_id}", status_code=204)
def delete_zone(item_id: UUID): return _delete("zones", item_id)


@app.get("/api/v1/management/access-points")
def list_access_points(floor_id: UUID | None = None):
    return _rows("SELECT * FROM access_points WHERE (%s::uuid IS NULL OR floor_id=%s) ORDER BY name NULLS LAST,serial", (floor_id, floor_id))


@app.post("/api/v1/management/access-points", status_code=201)
def create_access_point(item: AccessPointIn):
    return _one("""INSERT INTO access_points(id,floor_id,zone_id,serial,name,mac_address,x,y,active) VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING *""",
                (uuid4(),item.floor_id,item.zone_id,item.serial,item.name,item.mac_address,item.x,item.y,item.active))


@app.put("/api/v1/management/access-points/{item_id}")
def update_access_point(item_id: UUID, item: AccessPointIn):
    return _one("""UPDATE access_points SET floor_id=%s,zone_id=%s,serial=%s,name=%s,mac_address=%s,x=%s,y=%s,active=%s,updated_at=NOW() WHERE id=%s RETURNING *""",
                (item.floor_id,item.zone_id,item.serial,item.name,item.mac_address,item.x,item.y,item.active,item_id))


@app.delete("/api/v1/management/access-points/{item_id}", status_code=204)
def delete_access_point(item_id: UUID): return _delete("access_points", item_id)


@app.get("/api/v1/management/desks")
def list_desks(floor_id: UUID | None = None):
    return _rows("SELECT * FROM desks WHERE (%s::uuid IS NULL OR floor_id=%s) ORDER BY name", (floor_id, floor_id))


@app.post("/api/v1/management/desks", status_code=201)
def create_desk(item: DeskIn):
    return _one("""INSERT INTO desks(id,floor_id,zone_id,name,x,y,active) VALUES(%s,%s,%s,%s,%s,%s,%s) RETURNING *""",
                (uuid4(),item.floor_id,item.zone_id,item.name,item.x,item.y,item.active))


@app.put("/api/v1/management/desks/{item_id}")
def update_desk(item_id: UUID, item: DeskIn):
    return _one("""UPDATE desks SET floor_id=%s,zone_id=%s,name=%s,x=%s,y=%s,active=%s,updated_at=NOW() WHERE id=%s RETURNING *""",
                (item.floor_id,item.zone_id,item.name,item.x,item.y,item.active,item_id))


@app.delete("/api/v1/management/desks/{item_id}", status_code=204)
def delete_desk(item_id: UUID): return _delete("desks", item_id)


@app.get("/api/v1/management/floors/{floor_id}/layout")
def floor_layout(floor_id: UUID):
    floor = _one("SELECT * FROM floors WHERE id=%s", (floor_id,))
    zones = _rows("SELECT * FROM zones WHERE floor_id=%s ORDER BY name", (floor_id,))
    desks = _rows("SELECT * FROM desks WHERE floor_id=%s ORDER BY name", (floor_id,))
    aps = _rows("SELECT * FROM access_points WHERE floor_id=%s ORDER BY name NULLS LAST,serial", (floor_id,))
    return {"floor": floor, "zones": zones, "desks": desks, "access_points": aps, "generated_at": datetime.now(timezone.utc)}
