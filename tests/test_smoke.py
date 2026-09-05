from fastapi.testclient import TestClient

from app.main import app


def test_index_renders():
    with TestClient(app) as client:
        r = client.get("/")
        assert r.status_code == 200
        assert "Schema VCS" in r.text