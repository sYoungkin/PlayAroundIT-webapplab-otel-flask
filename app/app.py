from flask import Flask, request, jsonify, g
from logging.handlers import RotatingFileHandler
import logging
import json
import time
import uuid
import random

app = Flask(__name__)

app_logger = logging.getLogger("webapplab")
app_logger.setLevel(logging.INFO)

handler = RotatingFileHandler(
    "/var/log/webapplab/app.jsonl",
    maxBytes=5_000_000,
    backupCount=3
)
handler.setFormatter(logging.Formatter("%(message)s"))
app_logger.addHandler(handler)


@app.before_request
def before_request():
    g.start_time = time.time()
    g.request_id = str(uuid.uuid4())


@app.after_request
def after_request(response):
    duration_ms = round((time.time() - g.start_time) * 1000, 2)

    event = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "request_id": g.request_id,
        "remote_addr": request.remote_addr,
        "method": request.method,
        "path": request.path,
        "status_code": response.status_code,
        "duration_ms": duration_ms,
        "user_agent": request.headers.get("User-Agent"),
        "host": request.headers.get("Host")
    }

    app_logger.info(json.dumps(event))
    response.headers["X-Request-ID"] = g.request_id
    return response


@app.route("/")
def index():
    return """
    <h1>Hello from the backend Flask app</h1>
    <p>This request reached Flask through Apache reverse proxy.</p>
    """


@app.route("/api/health")
def health():
    return jsonify({
        "status": "ok",
        "service": "webapplab",
        "request_id": g.request_id
    })


@app.route("/api/login")
def login():
    user = request.args.get("user", "anonymous")
    result = random.choice(["success", "success", "success", "failure"])

    status_code = 200 if result == "success" else 401

    return jsonify({
        "event_type": "login",
        "user": user,
        "result": result,
        "request_id": g.request_id
    }), status_code


@app.route("/api/slow")
def slow():
    delay = random.choice([0.5, 1, 2, 3])
    time.sleep(delay)

    return jsonify({
        "status": "ok",
        "message": "This endpoint intentionally waited.",
        "delay_seconds": delay,
        "request_id": g.request_id
    })


@app.route("/api/random")
def random_endpoint():
    delay = random.choice([0, 0.05, 0.1, 0.25, 1.5])
    time.sleep(delay)

    if random.random() < 0.15:
        return jsonify({
            "status": "error",
            "message": "Simulated random backend error",
            "request_id": g.request_id
        }), 500

    return jsonify({
        "status": "ok",
        "delay_seconds": delay,
        "request_id": g.request_id
    })


@app.route("/api/error")
def error():
    return jsonify({
        "status": "error",
        "message": "Intentional lab error",
        "request_id": g.request_id
    }), 500


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000)