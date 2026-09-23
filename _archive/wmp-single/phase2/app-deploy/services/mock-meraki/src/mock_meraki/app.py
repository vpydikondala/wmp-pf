from __future__ import annotations

from fastapi import FastAPI, Header, HTTPException, Response

app = FastAPI(title="Mock Meraki API", version="1.0.0")
_state = {"status": 200}


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/control/status/{code}")
def set_status(code: int):
    _state["status"] = code
    return {"status": code}


def _check(auth: str | None):
    if auth != "Bearer integration-api-key":
        raise HTTPException(status_code=401, detail="unauthorised")
    if _state["status"] == 429:
        return Response(status_code=429, headers={"Retry-After": "1"})
    if _state["status"] >= 400:
        return Response(status_code=_state["status"])
    return None


@app.get("/api/v1/organizations")
def organizations(authorization: str | None = Header(default=None)):
    error = _check(authorization)
    if error:
        return error
    return [{"id": "org-1", "name": "Integration Organisation", "organizationId": "org-1"}]


@app.get("/api/v1/organizations/{org_id}/networks")
def networks(org_id: str, authorization: str | None = Header(default=None)):
    error = _check(authorization)
    if error:
        return error
    return [{"id": "net-1", "name": "Integration Network", "organizationId": org_id}]
