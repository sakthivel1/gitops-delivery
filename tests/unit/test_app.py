import pytest
from src.app import create_app


@pytest.fixture
def app():
    application = create_app()
    application.config["TESTING"] = True
    application.config["DATABASE_URL"] = ""  # no DB in unit tests
    return application


@pytest.fixture
def client(app):
    return app.test_client()


def test_healthz_returns_200(client):
    response = client.get("/healthz")
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "ok"
    assert "uptime" in data


def test_ready_returns_200_without_db(client):
    response = client.get("/ready")
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "ready"


def test_metrics_returns_200(client):
    response = client.get("/metrics")
    assert response.status_code == 200
    assert b"http_requests_total" in response.data


def test_list_transactions_without_db_returns_empty(client):
    response = client.get("/api/v1/transactions")
    assert response.status_code == 200
    assert response.get_json()["transactions"] == []


def test_create_transaction_missing_amount(client):
    response = client.post("/api/v1/transactions", json={"description": "test"})
    assert response.status_code == 400
    assert "amount" in response.get_json()["error"]


def test_create_transaction_invalid_amount(client):
    response = client.post("/api/v1/transactions", json={"amount": "not-a-number"})
    assert response.status_code == 400


def test_create_transaction_without_db_returns_201(client):
    response = client.post("/api/v1/transactions", json={"amount": 42.50, "description": "salary"})
    assert response.status_code == 201
    data = response.get_json()
    assert data["amount"] == 42.50
    assert data["description"] == "salary"
