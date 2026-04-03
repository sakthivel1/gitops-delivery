import os
import time
import logging

from flask import Flask, jsonify, request
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

from src.database import get_db_connection, init_db

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

REQUEST_COUNT = Counter(
    "http_requests_total", "Total HTTP requests", ["method", "endpoint", "status"]
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds", "HTTP request latency", ["endpoint"]
)

_start_time = time.time()


def create_app():
    app = Flask(__name__)
    app.config["DATABASE_URL"] = os.environ.get("DATABASE_URL", "")
    app.config["APP_ENV"] = os.environ.get("APP_ENV", "development")

    if app.config["DATABASE_URL"]:
        with app.app_context():
            init_db(app.config["DATABASE_URL"])

    @app.route("/healthz")
    def healthz():
        return jsonify({"status": "ok", "uptime": time.time() - _start_time}), 200

    @app.route("/ready")
    def ready():
        db_url = app.config["DATABASE_URL"]
        if db_url:
            try:
                conn = get_db_connection(db_url)
                conn.close()
            except Exception as exc:
                logger.warning("Readiness check failed: %s", exc)
                return jsonify({"status": "not ready", "reason": str(exc)}), 503
        return jsonify({"status": "ready"}), 200

    @app.route("/metrics")
    def metrics():
        return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}

    @app.route("/api/v1/transactions", methods=["GET"])
    def list_transactions():
        start = time.time()
        db_url = app.config["DATABASE_URL"]
        if not db_url:
            return jsonify({"transactions": []}), 200
        try:
            conn = get_db_connection(db_url)
            cur = conn.cursor()
            cur.execute("SELECT id, amount, description, created_at FROM transactions ORDER BY created_at DESC LIMIT 100")
            rows = cur.fetchall()
            conn.close()
            transactions = [
                {"id": r[0], "amount": str(r[1]), "description": r[2], "created_at": r[3].isoformat()}
                for r in rows
            ]
            REQUEST_COUNT.labels("GET", "/api/v1/transactions", "200").inc()
            REQUEST_LATENCY.labels("/api/v1/transactions").observe(time.time() - start)
            return jsonify({"transactions": transactions}), 200
        except Exception as exc:
            logger.error("Error fetching transactions: %s", exc)
            REQUEST_COUNT.labels("GET", "/api/v1/transactions", "500").inc()
            return jsonify({"error": "internal server error"}), 500

    @app.route("/api/v1/transactions", methods=["POST"])
    def create_transaction():
        start = time.time()
        data = request.get_json(silent=True) or {}
        amount = data.get("amount")
        description = data.get("description", "")

        if amount is None:
            return jsonify({"error": "amount is required"}), 400

        try:
            amount = float(amount)
        except (TypeError, ValueError):
            return jsonify({"error": "amount must be a number"}), 400

        db_url = app.config["DATABASE_URL"]
        if not db_url:
            return jsonify({"id": 0, "amount": amount, "description": description}), 201

        try:
            conn = get_db_connection(db_url)
            cur = conn.cursor()
            cur.execute(
                "INSERT INTO transactions (amount, description) VALUES (%s, %s) RETURNING id, created_at",
                (amount, description),
            )
            row = cur.fetchone()
            conn.commit()
            conn.close()
            REQUEST_COUNT.labels("POST", "/api/v1/transactions", "201").inc()
            REQUEST_LATENCY.labels("/api/v1/transactions").observe(time.time() - start)
            return jsonify({"id": row[0], "amount": amount, "description": description, "created_at": row[1].isoformat()}), 201
        except Exception as exc:
            logger.error("Error creating transaction: %s", exc)
            REQUEST_COUNT.labels("POST", "/api/v1/transactions", "500").inc()
            return jsonify({"error": "internal server error"}), 500

    return app


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app = create_app()
    app.run(host="0.0.0.0", port=port)
