from fastapi.testclient import TestClient

from app import app


client = TestClient(app)


def test_stats_endpoint_shape():
    response = client.get("/stats")
    assert response.status_code == 200
    body = response.json()
    assert "visitors" in body
    assert "users" in body
    assert "downloads" in body
    assert "mobile" in body["downloads"]
    assert "desktop" in body["downloads"]
    assert "total" in body["downloads"]


def test_track_visit_increments_count():
    before = client.get("/stats").json()["visitors"]
    client.post("/stats/visit")
    after = client.get("/stats").json()["visitors"]
    assert after == before + 1


def test_track_download_rejects_bad_platform():
    response = client.post("/stats/download/tablet")
    assert response.status_code == 400