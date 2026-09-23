from management_service.app import app, BuildingIn, AccessPointIn


def test_management_routes_registered():
    paths = {route.path for route in app.routes}
    assert "/health" in paths
    assert "/management/" in paths
    assert "/api/v1/management/buildings" in paths
    assert "/api/v1/management/floors" in paths
    assert "/api/v1/management/zones" in paths
    assert "/api/v1/management/access-points" in paths
    assert "/api/v1/management/desks" in paths


def test_models():
    b = BuildingIn(name="HQ")
    assert b.timezone == "Europe/London"
    ap = AccessPointIn(serial="Q2XX-1234")
    assert ap.active is True
