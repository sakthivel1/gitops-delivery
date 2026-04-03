import os
import pytest
from src.app import create_app


DATABASE_URL = os.environ.get("DATABASE_URL", "")


@pytest.fixture(scope="module")
def app():
    application = create_app()
    application.config["TESTING"] = True
    application.config["DATABASE_URL"] = DATABASE_URL
    return application


@pytest.fixture(scope="module")
def client(app):
    return app.test_client()


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL not set")
def test_create_and_list_transaction(client):
    # Create
    response = client.post(
        "/api/v1/transactions",
        json={"amount": 100.00, "description": "integration test payment"},
    )
    assert response.status_code == 201
    created = response.get_json()
    assert created["id"] > 0
    assert float(created["amount"]) == 100.00

    # List — the created record should appear
    response = client.get("/api/v1/transactions")
    assert response.status_code == 200
    ids = [t["id"] for t in response.get_json()["transactions"]]
    assert created["id"] in ids


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL not set")
def test_ready_with_db(client):
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.get_json()["status"] == "ready"


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL not set")
def test_healthz(client):
    response = client.get("/healthz")
    assert response.status_code == 200
