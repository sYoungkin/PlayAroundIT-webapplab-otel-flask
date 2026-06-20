# 04 — WebAppLab Troubleshooting Cheat Sheet

## Purpose

This cheat sheet provides quick troubleshooting commands for the WebAppLab project.

It covers:

```text id="y0kyjo"
Apache reverse proxy
Flask backend app
OpenTelemetry Collector
Jaeger
Vagrant port forwarding
Logs
Common HTTP status codes
```

---

# 1. Architecture Reference

## Request Path

```text id="8niqnx"
Mac browser / curl
  -> http://webapplab.test:8080
  -> Vagrant port forward: Mac 8080 -> VM 80
  -> Apache2 VirtualHost: webapplab.test
  -> ProxyPass /app/ -> http://127.0.0.1:5000/
  -> Flask application
```

## Telemetry Path

```text id="2k51wm"
Flask app with OpenTelemetry instrumentation
  -> OTLP/gRPC 127.0.0.1:4317
  -> OpenTelemetry Collector
  -> OTLP/gRPC 127.0.0.1:14317
  -> Jaeger
  -> Jaeger UI on http://localhost:16686
```

---

# 2. Important URLs

From the Mac host:

```text id="66b6hp"
Apache static page:
http://webapplab.test:8080/

Flask app through Apache:
http://webapplab.test:8080/app/

Flask health endpoint:
http://webapplab.test:8080/app/api/health

Jaeger UI:
http://localhost:16686
```

Inside the VM:

```text id="4dlkgt"
Apache local:
http://127.0.0.1/

Flask direct:
http://127.0.0.1:5000/

Jaeger UI:
http://127.0.0.1:16686

OpenTelemetry Collector internal metrics:
http://127.0.0.1:8889/metrics
```

---

# 3. Start Flask Manually

During development, the Flask app is started manually.

Without OpenTelemetry:

```bash id="lloz0o"
cd /home/vagrant/flask-lab
source venv/bin/activate
python app.py
```

With OpenTelemetry auto-instrumentation:

```bash id="t8w5cj"
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

Expected:

```text id="to8dmj"
Running on http://127.0.0.1:5000
```

---

# 4. Service Status Checks

## Apache

```bash id="pm4adp"
sudo systemctl status apache2 --no-pager
```

Restart Apache:

```bash id="6lelvx"
sudo systemctl restart apache2
```

Reload Apache after config changes:

```bash id="hflhn8"
sudo apache2ctl configtest
sudo systemctl reload apache2
```

## Jaeger

```bash id="76lsy3"
sudo systemctl status jaeger --no-pager
```

Recent logs:

```bash id="qdvzgi"
sudo journalctl -u jaeger -n 100 --no-pager
```

Follow logs:

```bash id="msw967"
sudo journalctl -u jaeger -f
```

## OpenTelemetry Collector

```bash id="5v3n4w"
sudo systemctl status otelcol --no-pager
```

Recent logs:

```bash id="32zabg"
sudo journalctl -u otelcol -n 100 --no-pager
```

Follow logs:

```bash id="wlzbr3"
sudo journalctl -u otelcol -f
```

---

# 5. Port Checks

Check all important ports:

```bash id="ndjijv"
sudo ss -tulpn | egrep '80|5000|4317|4318|14317|14318|16686|8888|8889'
```

Expected working state:

```text id="yxi0r6"
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

Check only Flask:

```bash id="u5uhbt"
sudo ss -tulpn | grep ':5000'
```

Check only Apache:

```bash id="w0e22w"
sudo ss -tulpn | grep ':80'
```

Check only Collector OTLP:

```bash id="qd766c"
sudo ss -tulpn | egrep '4317|4318'
```

Check only Jaeger:

```bash id="ejrfto"
sudo ss -tulpn | egrep '14317|14318|16686'
```

---

# 6. Curl Tests from Inside the VM

## Flask Direct

This bypasses Apache completely.

```bash id="n4qxf9"
curl -i http://127.0.0.1:5000/
curl -i http://127.0.0.1:5000/api/health
curl -i http://127.0.0.1:5000/api/random
curl -i http://127.0.0.1:5000/api/slow
curl -i http://127.0.0.1:5000/api/error
```

Interpretation:

```text id="q2bh4z"
Works here, fails through Apache:
  Apache/proxy issue

Fails here:
  Flask app issue or Flask not running
```

## Apache Static Site

```bash id="brt3e9"
curl -i -H "Host: webapplab.test" http://127.0.0.1/
```

Expected:

```text id="l95hvz"
HTTP/1.1 200 OK
```

## Apache Reverse Proxy to Flask

```bash id="y0mnrp"
curl -i -H "Host: webapplab.test" http://127.0.0.1/app/
curl -i -H "Host: webapplab.test" http://127.0.0.1/app/api/health
curl -i -H "Host: webapplab.test" http://127.0.0.1/app/api/random
curl -i -H "Host: webapplab.test" http://127.0.0.1/app/api/slow
curl -i -H "Host: webapplab.test" http://127.0.0.1/app/api/error
```

Expected for health:

```text id="97pdjd"
HTTP/1.1 200 OK
```

Expected for intentional error endpoint:

```text id="ekmq16"
HTTP/1.1 500 INTERNAL SERVER ERROR
```

---

# 7. Curl Tests from Mac Host

## Apache Static Page

```bash id="xxyras"
curl -i http://webapplab.test:8080/
```

## Flask Through Apache Reverse Proxy

```bash id="pqm3ns"
curl -i http://webapplab.test:8080/app/
curl -i http://webapplab.test:8080/app/api/health
curl -i http://webapplab.test:8080/app/api/random
curl -i http://webapplab.test:8080/app/api/slow
curl -i http://webapplab.test:8080/app/api/error
```

## Login Simulation

```bash id="gzhyte"
curl -i "http://webapplab.test:8080/app/api/login?user=steven"
curl -i "http://webapplab.test:8080/app/api/login?user=admin"
curl -i "http://webapplab.test:8080/app/api/login?user=guest"
```

---

# 8. Traffic Generation

## Random Backend Traffic

From the Mac host:

```bash id="0evvit"
for i in {1..50}; do
  curl -s -o /dev/null -w "%{http_code} %{time_total}\n" http://webapplab.test:8080/app/api/random
done
```

## Login Traffic

```bash id="6k7k6m"
for user in alice bob charlie diana admin guest; do
  curl -s "http://webapplab.test:8080/app/api/login?user=$user"
  echo
done
```

## Slow Endpoint Traffic

```bash id="kbhnoz"
for i in {1..10}; do
  curl -s -o /dev/null -w "%{http_code} %{time_total}\n" http://webapplab.test:8080/app/api/slow
done
```

---

# 9. Logs to Watch

## Apache Access Log

```bash id="1yhnhf"
sudo tail -f /var/log/apache2/webapplab-access.log
```

Shows:

```text id="1eftem"
client IP
request path
HTTP status
user agent
duration_us
request_id
```

## Apache Error Log

```bash id="l8keap"
sudo tail -f /var/log/apache2/webapplab-error.log
```

Useful for:

```text id="1ku9ct"
proxy errors
backend unavailable errors
Apache config/runtime errors
```

## Flask JSON App Log

```bash id="tuofp2"
tail -f /var/log/webapplab/app.jsonl
```

Shows structured application logs generated by the Flask app.

## Flask Foreground Terminal

If the app is run manually with:

```bash id="5xbb5n"
python app.py
```

or:

```bash id="7bf5sc"
opentelemetry-instrument python app.py
```

watch the terminal for:

```text id="815cj2"
Flask request logs
Python exceptions
stack traces
OpenTelemetry startup/runtime errors
```

## Jaeger Logs

```bash id="al4on8"
sudo journalctl -u jaeger -f
```

## OpenTelemetry Collector Logs

```bash id="zg6aa5"
sudo journalctl -u otelcol -f
```

---

# 10. Apache Config Checks

## Show Active Virtual Hosts

```bash id="ia9x3p"
sudo apache2ctl -S
```

Expected:

```text id="ncgpwy"
*:80 webapplab.test
```

## Check Enabled Sites

```bash id="ra07pa"
ls -l /etc/apache2/sites-enabled/
```

Expected:

```text id="7rwz85"
webapplab.conf -> ../sites-available/webapplab.conf
```

## Confirm ProxyPass Is Active

```bash id="cb0s74"
sudo grep -Rni "ServerName\|DocumentRoot\|ProxyPass\|ProxyPassReverse" /etc/apache2/sites-enabled/
```

Expected:

```text id="rkyzwx"
ServerName webapplab.test
DocumentRoot /var/www/webapplab
ProxyPass "/app/" "http://127.0.0.1:5000/"
ProxyPassReverse "/app/" "http://127.0.0.1:5000/"
```

## Check Proxy Modules

```bash id="m6jgtb"
apache2ctl -M | grep proxy
```

Expected:

```text id="qj75ne"
proxy_module
proxy_http_module
```

If missing:

```bash id="kt5lfp"
sudo a2enmod proxy proxy_http
sudo systemctl restart apache2
```

---

# 11. Jaeger and Collector Config Checks

## Check Jaeger Config

```bash id="0tq4fz"
sudo grep -Rni "16686\|14317\|14318\|jaeger_query\|jaeger_storage" /etc/jaeger/config.yaml
```

Expected important values:

```text id="e6iwqx"
0.0.0.0:16686
127.0.0.1:14317
127.0.0.1:14318
jaeger_query
jaeger_storage
```

## Check Collector Config

```bash id="f5e8lc"
sudo grep -Rni "4317\|4318\|14317\|8889\|otlp/jaeger\|debug" /etc/otelcol/config.yaml
```

Expected important values:

```text id="193pcz"
127.0.0.1:4317
127.0.0.1:4318
127.0.0.1:14317
127.0.0.1:8889
otlp/jaeger
debug
```

---

# 12. HTTP Status Code Interpretation

## 200 OK

Meaning:

```text id="p9n7cr"
Everything worked.
```

Example:

```bash id="c51mrq"
curl -i http://webapplab.test:8080/app/api/health
```

## 404 Not Found

Possible meanings:

```text id="svkkyj"
wrong URL path
Apache did not proxy the request
ProxyPass rule is not active
wrong Apache vhost
Flask route does not exist
```

How to distinguish:

```text id="qfwj0t"
Apache access log shows 404, Flask terminal shows nothing:
  Apache did not proxy the request.

Flask terminal shows request and 404:
  Flask received the request, but route does not exist.
```

## 500 Internal Server Error

Possible meaning:

```text id="va90hf"
Flask route executed but returned or raised an application error.
```

Check:

```bash id="thdxk0"
tail -f /var/log/webapplab/app.jsonl
```

Also check the Flask foreground terminal for stack traces.

## 503 Service Unavailable

Possible meaning:

```text id="9iqseq"
Apache reverse proxy is working,
but the Flask backend is unavailable.
```

Most common cause:

```text id="i2jqz8"
Flask app is not running on 127.0.0.1:5000.
```

Check:

```bash id="8fgj2n"
sudo ss -tulpn | grep ':5000'
curl -i http://127.0.0.1:5000/api/health
sudo tail -n 50 /var/log/apache2/webapplab-error.log
```

Typical Apache error log:

```text id="3753dg"
failed to make connection to backend: 127.0.0.1
attempt to connect to 127.0.0.1:5000 failed
```

## Connection Refused from Mac

Possible causes:

```text id="j1zf74"
Vagrant port forwarding issue
Apache not running
wrong host port
Mac /etc/hosts issue
```

Check from Mac:

```bash id="jav00n"
curl -i http://webapplab.test:8080/
```

Check inside VM:

```bash id="bbhzcq"
sudo systemctl status apache2 --no-pager
sudo ss -tulpn | grep ':80'
```

---

# 13. Troubleshooting Decision Tree

## Step 1 — Does Flask Work Directly?

Inside VM:

```bash id="5lsob0"
curl -i http://127.0.0.1:5000/api/health
```

Result:

```text id="wj1bq0"
200:
  Flask is healthy. Continue.

Connection refused / no response:
  Start or fix Flask.
```

## Step 2 — Does Apache Proxy Work Inside VM?

Inside VM:

```bash id="5tsu73"
curl -i -H "Host: webapplab.test" http://127.0.0.1/app/api/health
```

Result:

```text id="em9i54"
200:
  Apache proxy is healthy. Continue.

404:
  Check ProxyPass, vhost, route path.

503:
  Apache is proxying, but Flask is unavailable.
```

## Step 3 — Does End-to-End Access Work from Mac?

From Mac:

```bash id="nkqy18"
curl -i http://webapplab.test:8080/app/api/health
```

Result:

```text id="00jqbx"
200:
  Full request path is healthy.

Connection issue:
  Check Vagrant port forwarding and Mac /etc/hosts.
```

## Step 4 — Are Traces Reaching Collector?

Inside VM:

```bash id="6lu6ps"
sudo journalctl -u otelcol -f
```

Generate traffic:

```bash id="7xlkuq"
curl -i http://webapplab.test:8080/app/api/health
```

Expected:

```text id="khzjtf"
Collector logs show spans for service.name=webapplab-flask.
```

## Step 5 — Are Traces Visible in Jaeger?

Open from Mac:

```text id="gct5dx"
http://localhost:16686
```

Expected:

```text id="csn5ov"
Service: webapplab-flask
Traces visible after traffic generation
```

---

# 14. Common Failure Scenarios

## Scenario: Apache Works, Flask Direct Fails

Symptoms:

```text id="3zpmyu"
curl http://webapplab.test:8080/ works
curl http://127.0.0.1:5000/api/health fails
```

Meaning:

```text id="m7orl9"
Apache is fine.
Flask is not running or crashed.
```

Fix:

```bash id="ynx6kf"
cd /home/vagrant/flask-lab
source venv/bin/activate
python app.py
```

or with OpenTelemetry:

```bash id="sxxbnk"
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

## Scenario: Flask Direct Works, Apache Proxy Fails with 404

Meaning:

```text id="x5x883"
Apache is not applying the ProxyPass rule,
or the wrong enabled vhost is being used.
```

Check:

```bash id="jpznrn"
sudo apache2ctl -S
ls -l /etc/apache2/sites-enabled/
sudo grep -Rni "ProxyPass" /etc/apache2/sites-enabled/
```

## Scenario: Flask Direct Works, Apache Proxy Fails with 503

Meaning:

```text id="9h9f29"
Apache is trying to proxy,
but cannot reach Flask.
```

Check:

```bash id="ksz9uk"
sudo tail -n 50 /var/log/apache2/webapplab-error.log
sudo ss -tulpn | grep ':5000'
```

## Scenario: App Works, But No Traces in Jaeger

Meaning:

```text id="ai600f"
Flask may not be running through opentelemetry-instrument,
or the Collector/Jaeger pipeline is broken.
```

Check:

```bash id="2uzbal"
sudo systemctl status otelcol --no-pager
sudo systemctl status jaeger --no-pager
sudo ss -tulpn | egrep '4317|14317'
sudo journalctl -u otelcol -n 100 --no-pager
```

Confirm app was started with:

```bash id="xmx3tm"
opentelemetry-instrument python app.py
```

## Scenario: Collector Fails to Start Because Port 8888 Is in Use

Error:

```text id="54g37x"
binding address localhost:8888 for Prometheus exporter:
listen tcp 127.0.0.1:8888: bind: address already in use
```

Meaning:

```text id="u91od7"
Jaeger and the Collector both tried to expose internal metrics on port 8888.
```

Fix:

Set Collector internal metrics to `8889`:

```yaml id="voqp29"
service:
  telemetry:
    metrics:
      readers:
        - pull:
            exporter:
              prometheus:
                host: 127.0.0.1
                port: 8889
```

Restart Collector:

```bash id="35btqy"
sudo systemctl restart otelcol
```

---

# 15. Fast Baseline Check

Run this after starting the VM:

```bash id="np8eqc"
sudo systemctl status apache2 --no-pager
sudo systemctl status jaeger --no-pager
sudo systemctl status otelcol --no-pager
sudo ss -tulpn | egrep '80|5000|4317|4318|14317|14318|16686|8888|8889'
```

Then start Flask manually:

```bash id="zdt28s"
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

From another terminal or Mac host:

```bash id="a7t0pa"
curl -i http://webapplab.test:8080/app/api/health
```

Open Jaeger:

```text id="04boyc"
http://localhost:16686
```

Search for service:

```text id="4tko1d"
webapplab-flask
```

---

# 16. Most Useful Commands

```bash id="b8lkno"
# Flask direct
curl -i http://127.0.0.1:5000/api/health

# Apache proxy inside VM
curl -i -H "Host: webapplab.test" http://127.0.0.1/app/api/health

# End-to-end from Mac
curl -i http://webapplab.test:8080/app/api/health

# Apache access log
sudo tail -f /var/log/apache2/webapplab-access.log

# Apache error log
sudo tail -f /var/log/apache2/webapplab-error.log

# Flask app JSON log
tail -f /var/log/webapplab/app.jsonl

# Active ports
sudo ss -tulpn | egrep '80|5000|4317|4318|14317|14318|16686|8888|8889'

# Active Apache vhost/proxy config
sudo apache2ctl -S
sudo grep -Rni "ProxyPass\|ServerName" /etc/apache2/sites-enabled/

# OTel Collector status
sudo systemctl status otelcol --no-pager
sudo journalctl -u otelcol -n 100 --no-pager

# Jaeger status
sudo systemctl status jaeger --no-pager
sudo journalctl -u jaeger -n 100 --no-pager
```

---

# 17. Healthy System Checklist

The system is healthy when:

```text id="fozjh2"
[ ] Apache is running
[ ] Jaeger is running
[ ] OpenTelemetry Collector is running
[ ] Flask is running on 127.0.0.1:5000
[ ] Apache proxy to /app/ works
[ ] End-to-end curl from Mac works
[ ] Collector receives spans
[ ] Jaeger displays traces for webapplab-flask
```

Expected working path:

```text id="1qg8mh"
curl/browser
  -> webapplab.test:8080
  -> Apache
  -> Flask
  -> OpenTelemetry Collector
  -> Jaeger
```
