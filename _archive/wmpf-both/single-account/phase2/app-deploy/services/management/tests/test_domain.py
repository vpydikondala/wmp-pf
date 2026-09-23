from pathlib import Path


def test_initial_migration_contains_management_tables():
    sql = Path("services/management/migrations/001_management_schema.sql").read_text()
    for table in ["buildings", "floors", "zones", "access_points", "desks"]:
        assert f"CREATE TABLE IF NOT EXISTS {table}" in sql
