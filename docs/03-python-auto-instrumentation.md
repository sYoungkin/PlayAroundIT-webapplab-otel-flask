# 03 — Python Auto-Instrumentation for Flask with OpenTelemetry

## Goal

Enable OpenTelemetry tracing for the Flask application without modifying the application code.

Instead of running the Flask app directly:

```bash id="okxh89"
python app.py
```

run it through the OpenTelemetry Python auto-instrumentation wrapper:

```bash id="x37fuo"
opentelemetry-instrument python app.py
```

This loads OpenTelemetry instrumentation into the Python process at startup and automatically instruments supported frameworks such as Flask.

---

# 1. Architecture

Current application path:

```text id="fpx72h"
Mac browser / curl
  -> http://webapplab.test:8080
  -> Vagrant port forward: host 8080 -> guest 80
  -> Apache reverse proxy
  -> Flask app
```

Telemetry path:

```text id="8ib94c"
Flask app with OpenTelemetry auto-instrumentation
  -> OTLP/gRPC 127.0.0.1:4317
  -> OpenTelemetry Collector
  -> OTLP/gRPC 127.0.0.1:14317
  -> Jaeger
  -> Jaeger UI on http://localhost:16686
```

Runtime model:

```text id="kemj2m"
Flask + OpenTelemetry instrumentation = same Python process
OpenTelemetry Collector              = separate systemd service
Jaeger                               = separate systemd service
```

The Collector and Jaeger run in the background. The Flask app is still run manually during development.

---

# 2. Prerequisites

The previous setup steps should already be complete:

```text id="j15d2c"
[ ] Apache reverse proxy works
[ ] Flask app works normally
[ ] Jaeger service is running
[ ] OpenTelemetry Collector service is running
[ ] Jaeger UI opens at http://localhost:16686
[ ] Collector listens on 127.0.0.1:4317
```

Check Jaeger:

```bash id="azh1io"
sudo systemctl status jaeger --no-pager
curl -i http://127.0.0.1:16686
```

Check Collector:

```bash id="anx7xz"
sudo systemctl status otelcol --no-pager
curl -i http://127.0.0.1:8889/metrics | head
```

Check application without instrumentation:

```bash id="bdgue9"
curl -i http://webapplab.test:8080/app/api/health
```

Expected:

```text id="dfgvlc"
HTTP/1.1 200 OK
```

---

# 3. Stop the Existing Flask Process

If the Flask app is already running normally, stop it in the Flask terminal:

```text id="smo5hk"
Ctrl+C
```

Confirm port `5000` is free:

```bash id="4m0fn7"
sudo ss -tulpn | grep ':5000'
```

No output means nothing is currently listening on port `5000`.

---

# 4. Activate the Flask Virtual Environment

Inside the VM:

```bash id="0bmw1p"
cd /home/vagrant/flask-lab
source venv/bin/activate
```

Verify that Python and pip are coming from the virtual environment:

```bash id="9e0mo9"
which python
which pip
```

Expected:

```text id="rdnoif"
/home/vagrant/flask-lab/venv/bin/python
/home/vagrant/flask-lab/venv/bin/pip
```

---

# 5. Install OpenTelemetry Python Packages

Upgrade pip:

```bash id="hbhmal"
pip install --upgrade pip
```

Install the OpenTelemetry distribution and OTLP exporter:

```bash id="8mq6wy"
pip install opentelemetry-distro opentelemetry-exporter-otlp
```

Install detected instrumentation packages automatically:

```bash id="bndekm"
opentelemetry-bootstrap -a install
```

This detects installed Python packages and installs matching OpenTelemetry instrumentation libraries.

Check installed OpenTelemetry packages:

```bash id="tbf31q"
pip list | grep opentelemetry
```

Expected package types include:

```text id="rvp1go"
opentelemetry-api
opentelemetry-sdk
opentelemetry-distro
opentelemetry-exporter-otlp
opentelemetry-instrumentation
opentelemetry-instrumentation-flask
opentelemetry-instrumentation-wsgi
```

The exact package list may vary depending on detected dependencies.

---

# 6. Run Flask with OpenTelemetry Auto-Instrumentation

From inside `/home/vagrant/flask-lab` with the virtual environment activated:

```bash id="sk31o6"
OTEL_SERVICE_NAME=webapplab-flask \
OTEL_TRACES_EXPORTER=otlp \
OTEL_METRICS_EXPORTER=none \
OTEL_LOGS_EXPORTER=none \
OTEL_EXPORTER_OTLP_PROTOCOL=grpc \
OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4317 \
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=lab,service.version=0.1.0 \
opentelemetry-instrument python app.py
```

Expected Flask output:

```text id="vcy8qr"
Running on http://127.0.0.1:5000
```

---

# 7. Environment Variable Explanation

## Service Name

```text id="d4sk36"
OTEL_SERVICE_NAME=webapplab-flask
```

Defines the service name that appears in Jaeger.

Expected Jaeger service:

```text id="eptb9u"
webapplab-flask
```

## Trace Exporter

```text id="lg8c2y"
OTEL_TRACES_EXPORTER=otlp
```

Exports traces using the OpenTelemetry Protocol.

## Disable Metrics and Logs for Now

```text id="aq9jih"
OTEL_METRICS_EXPORTER=none
OTEL_LOGS_EXPORTER=none
```

This lab phase focuses only on traces. Metrics and logs export are intentionally disabled for now.

## OTLP Protocol

```text id="g3qsfw"
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```

Uses OTLP over gRPC.

## Collector Endpoint

```text id="0hjnb5"
OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4317
```

Sends telemetry to the local OpenTelemetry Collector.

## Resource Attributes

```text id="1s3q1v"
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=lab,service.version=0.1.0
```

Adds metadata to telemetry emitted by the application.

These attributes can be used later for filtering and grouping traces.

---

# 8. Generate Test Traffic

From the Mac host:

```bash id="t1p5gs"
curl -i http://webapplab.test:8080/app/api/health
curl -i http://webapplab.test:8080/app/api/random
curl -i http://webapplab.test:8080/app/api/slow
curl -i http://webapplab.test:8080/app/api/error
```

Generate repeated random traffic:

```bash id="fg9yn0"
for i in {1..20}; do
  curl -s -o /dev/null -w "%{http_code} %{time_total}\n" http://webapplab.test:8080/app/api/random
done
```

Generate login traffic:

```bash id="zsipb0"
for user in alice bob charlie diana admin guest; do
  curl -s "http://webapplab.test:8080/app/api/login?user=$user"
  echo
done
```

Generate slow endpoint traffic:

```bash id="zyw4gb"
for i in {1..10}; do
  curl -s -o /dev/null -w "%{http_code} %{time_total}\n" http://webapplab.test:8080/app/api/slow
done
```

---

# 9. Verify Spans in the OpenTelemetry Collector

Watch Collector logs:

```bash id="bu8g9i"
sudo journalctl -u otelcol -f
```

Because the Collector configuration includes the debug exporter, spans should appear in the Collector logs when requests hit the Flask app.

Recent Collector logs:

```bash id="tfrq36"
sudo journalctl -u otelcol -n 100 --no-pager
```

Expected indicators:

```text id="ck7uz3"
service.name: webapplab-flask
http.method: GET
http.route: /api/health
http.status_code: 200
```

Exact attribute names may vary slightly depending on OpenTelemetry package versions.

---

# 10. Verify Traces in Jaeger

Open Jaeger from the Mac host:

```text id="l6tip8"
http://localhost:16686
```

In Jaeger:

```text id="xeqw11"
Service: webapplab-flask
```

Then click:

```text id="f6nfh6"
Find Traces
```

Expected operations include routes such as:

```text id="fjnr81"
GET /api/health
GET /api/random
GET /api/slow
GET /api/error
GET /api/login
```

Note: the browser calls Apache under `/app/...`, but Apache proxies to Flask without the `/app` prefix.

External request:

```text id="b15baj"
http://webapplab.test:8080/app/api/health
```

Flask receives:

```text id="b0vbp3"
/api/health
```

Therefore the Jaeger route appears as:

```text id="m1lusf"
GET /api/health
```

not:

```text id="w4lca7"
GET /app/api/health
```

---

# 11. Useful Verification Commands

## Flask Direct

```bash id="h74q4w"
curl -i http://127.0.0.1:5000/api/health
```

## Apache Reverse Proxy Inside VM

```bash id="66q56q"
curl -i -H "Host: webapplab.test" http://127.0.0.1/app/api/health
```

## End-to-End from Mac

```bash id="9hu8si"
curl -i http://webapplab.test:8080/app/api/health
```

## Collector Status

```bash id="qh1fof"
sudo systemctl status otelcol --no-pager
sudo journalctl -u otelcol -n 100 --no-pager
```

## Jaeger Status

```bash id="660fp5"
sudo systemctl status jaeger --no-pager
sudo journalctl -u jaeger -n 100 --no-pager
```

## Active Ports

```bash id="d3u1q9"
sudo ss -tulpn | egrep '80|5000|4317|4318|14317|14318|16686|8888|8889'
```

Expected:

```text id="y2w2sm"
0.0.0.0:80          Apache
127.0.0.1:5000      Flask app
127.0.0.1:4317      OpenTelemetry Collector OTLP/gRPC
127.0.0.1:4318      OpenTelemetry Collector OTLP/HTTP
127.0.0.1:14317     Jaeger OTLP/gRPC
127.0.0.1:14318     Jaeger OTLP/HTTP
0.0.0.0:16686       Jaeger UI
127.0.0.1:8888      Jaeger internal metrics
127.0.0.1:8889      OpenTelemetry Collector internal metrics
```

---

# 12. Troubleshooting

## Flask Does Not Start with Auto-Instrumentation

Try running Flask normally:

```bash id="lgr4if"
python app.py
```

If normal Flask fails, the issue is with the Flask app or Python environment, not OpenTelemetry.

If normal Flask works but auto-instrumentation fails, check:

```bash id="milrev"
which opentelemetry-instrument
pip list | grep opentelemetry
```

Expected:

```text id="x2x8zq"
/home/vagrant/flask-lab/venv/bin/opentelemetry-instrument
```

## Apache Returns 503

A `503 Service Unavailable` from Apache usually means Apache is working, but Flask is not running.

Check:

```bash id="csny52"
sudo ss -tulpn | grep ':5000'
curl -i http://127.0.0.1:5000/api/health
sudo tail -n 50 /var/log/apache2/webapplab-error.log
```

Most common cause:

```text id="898myc"
Flask app was not started or crashed.
```

Fix:

```bash id="g1qxpq"
cd /home/vagrant/flask-lab
source venv/bin/activate

OTEL_SERVICE_NAME=webapplab-flask \
OTEL_TRACES_EXPORTER=otlp \
OTEL_METRICS_EXPORTER=none \
OTEL_LOGS_EXPORTER=none \
OTEL_EXPORTER_OTLP_PROTOCOL=grpc \
OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4317 \
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=lab,service.version=0.1.0 \
opentelemetry-instrument python app.py
```

## App Works but Jaeger Shows No Traces

Check that Flask was started with:

```bash id="kxpg2f"
opentelemetry-instrument python app.py
```

not:

```bash id="oe57qh"
python app.py
```

Check Collector:

```bash id="yqcned"
sudo systemctl status otelcol --no-pager
sudo journalctl -u otelcol -n 100 --no-pager
```

Check Collector OTLP port:

```bash id="sqw2n7"
sudo ss -tulpn | grep ':4317'
```

Expected:

```text id="avpov3"
127.0.0.1:4317
```

Generate fresh traffic:

```bash id="55u4fj"
for i in {1..10}; do
  curl -s http://webapplab.test:8080/app/api/health > /dev/null
done
```

Refresh Jaeger and check for service:

```text id="zgmkxa"
webapplab-flask
```

## Collector Logs Show Export Errors

Check that Jaeger is running and listening on `14317`:

```bash id="p2e7xj"
sudo ss -tulpn | grep ':14317'
sudo systemctl status jaeger --no-pager
```

Check Collector config:

```bash id="5f5xcg"
sudo grep -Rni "14317\|4317\|otlp/jaeger\|debug" /etc/otelcol/config.yaml
```

Expected:

```text id="7fai8n"
endpoint: 127.0.0.1:4317
endpoint: 127.0.0.1:14317
otlp/jaeger
debug
```

---

# 13. Manual vs Auto-Instrumented Startup

Normal Flask startup:

```bash id="xn2k45"
python app.py
```

Auto-instrumented Flask startup:

```bash id="z82goa"
opentelemetry-instrument python app.py
```

Conceptual model:

```text id="glsyp7"
Auto-instrumentation is not a separate background process.
It is loaded into the Python application process at startup.
```

The application process still runs normally, but supported libraries are instrumented automatically.

```text id="td3cwo"
Flask app + OpenTelemetry instrumentation = same Python process
OpenTelemetry Collector                  = separate systemd service
Jaeger                                   = separate systemd service
```

---

# 14. Production-Like Note

In production, the application startup command would be modified to include `opentelemetry-instrument`.

For example, a normal service might run:

```bash id="osfpuc"
python app.py
```

The instrumented version would run:

```bash id="pnctkv"
opentelemetry-instrument python app.py
```

For a more production-like Flask deployment with Gunicorn:

```bash id="bw0xe5"
opentelemetry-instrument gunicorn app:app --bind 127.0.0.1:5000
```

In this lab, the Flask development server is acceptable while learning instrumentation concepts.

---

# 15. Final Working Command

The current working manual command is:

```bash id="l15zeg"
cd /home/vagrant/flask-lab
source venv/bin/activate

OTEL_SERVICE_NAME=webapplab-flask \
OTEL_TRACES_EXPORTER=otlp \
OTEL_METRICS_EXPORTER=none \
OTEL_LOGS_EXPORTER=none \
OTEL_EXPORTER_OTLP_PROTOCOL=grpc \
OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4317 \
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=lab,service.version=0.1.0 \
opentelemetry-instrument python app.py
```

---

# 16. Final Working State

This phase is complete when:

```text id="eeji9d"
[ ] Flask starts through opentelemetry-instrument
[ ] App works at http://webapplab.test:8080/app/api/health
[ ] Collector logs show received/exported spans
[ ] Jaeger UI shows service webapplab-flask
[ ] Jaeger contains traces for Flask routes
```

Successful telemetry path:

```text id="4vuwal"
Mac browser / curl
  -> Apache reverse proxy
  -> Flask app with OTel auto-instrumentation
  -> OpenTelemetry Collector
  -> Jaeger
  -> Jaeger UI
```

Next recommended step:

```text id="ro7ssf"
Add a second backend Flask service to create distributed traces with parent-child spans across services.
```
