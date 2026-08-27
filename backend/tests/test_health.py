from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_api_v1_health_ok():
    r = client.get("/api/v1/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_root():
    r = client.get("/")
    assert r.status_code == 200
    assert r.json()["service"]


def test_health_contract():
    """`GET /health` returns the documented shape - 200 when the DB is
    reachable, 503 with a reason when it is not."""
    r = client.get("/health")
    assert r.status_code in (200, 503)
    body = r.json()
    if r.status_code == 200:
        assert body == {"status": "ok", "db": "connected"}
    else:
        assert body["status"] == "error"
        assert body["db"] == "disconnected"
        assert body["reason"]
