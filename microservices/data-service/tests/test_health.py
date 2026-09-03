from fastapi.testclient import TestClient

from app.main import app


client = TestClient(app)


def test_health_check():
    response = client.get("/health")
    assert response.status_code == 200
    payload = response.json()
    # The service returns "status" plus a diagnostic flag reporting
    # whether GEMINI_API_KEY is configured (see main.py). Assert on the
    # required field only so adding future diagnostic fields doesn't
    # regress this test — that had happened once already when
    # "assistant_configured" landed here.
    assert payload["status"] == "ok"
    # The assistant flag is a boolean when present; it may be absent in
    # older builds, which is why this is a soft check rather than a
    # required key.
    if "assistant_configured" in payload:
        assert isinstance(payload["assistant_configured"], bool)
