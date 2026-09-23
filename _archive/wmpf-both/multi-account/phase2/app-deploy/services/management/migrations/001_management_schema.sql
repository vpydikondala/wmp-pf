CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS buildings (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL,
    code TEXT UNIQUE,
    address TEXT,
    timezone TEXT NOT NULL DEFAULT 'Europe/London',
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS floors (
    id UUID PRIMARY KEY,
    building_id UUID NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    floor_number INTEGER,
    map_width DOUBLE PRECISION NOT NULL DEFAULT 100,
    map_height DOUBLE PRECISION NOT NULL DEFAULT 100,
    floor_plan_s3_key TEXT,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(building_id, name)
);

CREATE TABLE IF NOT EXISTS zones (
    id UUID PRIMARY KEY,
    floor_id UUID NOT NULL REFERENCES floors(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    zone_type TEXT,
    polygon JSONB NOT NULL DEFAULT '[]'::jsonb,
    capacity INTEGER,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(floor_id, name)
);

CREATE TABLE IF NOT EXISTS access_points (
    id UUID PRIMARY KEY,
    floor_id UUID REFERENCES floors(id) ON DELETE SET NULL,
    zone_id UUID REFERENCES zones(id) ON DELETE SET NULL,
    serial TEXT NOT NULL UNIQUE,
    name TEXT,
    mac_address TEXT,
    x DOUBLE PRECISION,
    y DOUBLE PRECISION,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS desks (
    id UUID PRIMARY KEY,
    floor_id UUID NOT NULL REFERENCES floors(id) ON DELETE CASCADE,
    zone_id UUID REFERENCES zones(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    x DOUBLE PRECISION NOT NULL,
    y DOUBLE PRECISION NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(floor_id, name)
);

CREATE TABLE IF NOT EXISTS observations (
    id BIGSERIAL PRIMARY KEY,
    device_id TEXT NOT NULL,
    ts TIMESTAMPTZ NOT NULL,
    x DOUBLE PRECISION NOT NULL,
    y DOUBLE PRECISION NOT NULL,
    zone_id UUID REFERENCES zones(id) ON DELETE SET NULL,
    desk_id UUID REFERENCES desks(id) ON DELETE SET NULL,
    confidence DOUBLE PRECISION NOT NULL DEFAULT 1.0
);
CREATE INDEX IF NOT EXISTS ix_observations_device_ts ON observations(device_id, ts DESC);
CREATE INDEX IF NOT EXISTS ix_floors_building ON floors(building_id);
CREATE INDEX IF NOT EXISTS ix_zones_floor ON zones(floor_id);
CREATE INDEX IF NOT EXISTS ix_access_points_floor ON access_points(floor_id);
CREATE INDEX IF NOT EXISTS ix_access_points_zone ON access_points(zone_id);
CREATE INDEX IF NOT EXISTS ix_desks_floor ON desks(floor_id);
