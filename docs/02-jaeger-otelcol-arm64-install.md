# 02 — Jaeger v2 + OpenTelemetry Collector Local ARM64 Installation

## Goal

Install and configure a local tracing backend for the WebAppLab project without Docker.

This setup uses:

```text id="3hq9mm"
Jaeger v2
OpenTelemetry Collector
Ubuntu ARM64 VM
systemd services
in-memory Jaeger storage
OTLP/gRPC trace forwarding
```

The target architecture is:

```text id="33l5au"
Flask app
  -> OTLP/gRPC 127.0.0.1:4317
  -> OpenTelemetry Collector
  -> OTLP/gRPC 127.0.0.1:14317
  -> Jaeger v2
  -> Jaeger UI on 0.0.0.0:16686
  -> Mac browser via Vagrant port forwarding
```

This keeps the OpenTelemetry Collector as the central telemetry intake point. Jaeger is used as the trace storage and visualization backend.

---

# 1. Runtime Architecture

```text id="hbce87"
Application layer:
  Flask app running on 127.0.0.1:5000

Telemetry intake:
  OpenTelemetry Collector listening on 127.0.0.1:4317 and 127.0.0.1:4318

Tracing backend:
  Jaeger listening for OTLP on 127.0.0.1:14317 and 127.0.0.1:14318

UI:
  Jaeger UI exposed on 0.0.0.0:16686
```

Port summary:

```text id="o5uzl4"
127.0.0.1:4317      OpenTelemetry Collector OTLP/gRPC
127.0.0.1:4318      OpenTelemetry Collector OTLP/HTTP
127.0.0.1:14317     Jaeger OTLP/gRPC
127.0.0.1:14318     Jaeger OTLP/HTTP
0.0.0.0:16686       Jaeger UI
127.0.0.1:8888      Jaeger internal metrics
127.0.0.1:8889      OpenTelemetry Collector internal metrics
```

---

# 2. Vagrant Port Forwarding

The Apache web app already uses:

```ruby id="nqjru7"
config.vm.network "forwarded_port", guest: 80, host: 8080
```

Add Jaeger UI forwarding:

```ruby id="jg9h4z"
config.vm.network "forwarded_port", guest: 16686, host: 16686
```

Optional, only if OTLP traffic should be tested directly from the Mac host:

```ruby id="m7cqbq"
config.vm.network "forwarded_port", guest: 4317, host: 4317
config.vm.network "forwarded_port", guest: 4318, host: 4318
```

Reload the VM after changing the `Vagrantfile`:

```bash id="iyygpp"
vagrant reload
```

Jaeger UI should later be reachable from the Mac host at:

```text id="gxjj1v"
http://localhost:16686
```

---

# 3. Confirm ARM64 Architecture

Inside the VM:

```bash id="v1kfd9"
dpkg --print-architecture
uname -m
```

Expected:

```text id="tcaysh"
arm64
aarch64
```

On Ubuntu/Debian, the package architecture name is `arm64`. The kernel/CPU architecture often appears as `aarch64`.

---

# 4. Install Jaeger v2 ARM64 Binary

## Download Jaeger

Inside the VM:

```bash id="6vhtjf"
cd /tmp

JAEGER_VERSION=2.19.0
JAEGER_ARCH=arm64

wget https://github.com/jaegertracing/jaeger/releases/download/v${JAEGER_VERSION}/jaeger-${JAEGER_VERSION}-linux-${JAEGER_ARCH}.tar.gz
```

Extract:

```bash id="g4w2pn"
tar -xzf jaeger-${JAEGER_VERSION}-linux-${JAEGER_ARCH}.tar.gz
```

Install binary:

```bash id="5bl8pp"
sudo install -m 0755 jaeger-${JAEGER_VERSION}-linux-${JAEGER_ARCH}/jaeger /usr/local/bin/jaeger
```

Verify:

```bash id="ud4ths"
/usr/local/bin/jaeger --help | head
```

Expected: Jaeger help output.

---

# 5. Create Jaeger Config

Create config directory:

```bash id="q4qg61"
sudo mkdir -p /etc/jaeger
```

Create config file:

```bash id="r1pydi"
sudo nano /etc/jaeger/config.yaml
```

Paste:

```yaml id="u23pj9"
extensions:
  jaeger_storage:
    backends:
      memstore:
        memory:
          max_traces: 100000

  jaeger_query:
    storage:
      traces: memstore
    base_path: /
    http:
      endpoint: 0.0.0.0:16686
    grpc:
      endpoint: 127.0.0.1:16685

receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 127.0.0.1:14317
      http:
        endpoint: 127.0.0.1:14318

processors:
  batch:

exporters:
  jaeger_storage_exporter:
    trace_storage: memstore

service:
  extensions: [jaeger_storage, jaeger_query]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [jaeger_storage_exporter]
```

Runtime location:

```text id="jobamo"
/etc/jaeger/config.yaml
```

Repository location:

```text id="sua6kq"
jaeger/jaeger-config.yaml
```

## Jaeger Port Design

Jaeger receives OTLP telemetry on nonstandard local ports:

```text id="k3z96v"
Jaeger OTLP/gRPC: 127.0.0.1:14317
Jaeger OTLP/HTTP: 127.0.0.1:14318
```

This avoids a conflict with the OpenTelemetry Collector, which uses the standard OTLP ports:

```text id="29fv0p"
Collector OTLP/gRPC: 127.0.0.1:4317
Collector OTLP/HTTP: 127.0.0.1:4318
```

---

# 6. Create Jaeger systemd Service

Create a dedicated service user:

```bash id="jrvt5c"
id -u jaeger >/dev/null 2>&1 || sudo useradd --system --no-create-home --shell /usr/sbin/nologin jaeger
```

Create the systemd unit:

```bash id="zlaq13"
sudo nano /etc/systemd/system/jaeger.service
```

Paste:

```ini id="9x2m1b"
[Unit]
Description=Jaeger v2 local tracing backend
After=network-online.target
Wants=network-online.target

[Service]
User=jaeger
Group=jaeger
ExecStart=/usr/local/bin/jaeger --config /etc/jaeger/config.yaml
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

Reload systemd:

```bash id="66ru1s"
sudo systemctl daemon-reload
```

Enable and start Jaeger:

```bash id="eoqngi"
sudo systemctl enable --now jaeger
```

Check service:

```bash id="vu9ezy"
sudo systemctl status jaeger --no-pager
```

Check logs:

```bash id="clwn1s"
sudo journalctl -u jaeger -n 100 --no-pager
```

Check Jaeger ports:

```bash id="fhg5h2"
sudo ss -tulpn | egrep '16686|14317|14318|16685|8888'
```

Expected:

```text id="4ompvy"
0.0.0.0:16686       Jaeger UI
127.0.0.1:14317     Jaeger OTLP/gRPC receiver
127.0.0.1:14318     Jaeger OTLP/HTTP receiver
127.0.0.1:16685     Jaeger query gRPC
127.0.0.1:8888      Jaeger internal metrics
```

Test Jaeger UI from inside the VM:

```bash id="fgnkrl"
curl -i http://127.0.0.1:16686
```

Test Jaeger UI from the Mac host:

```text id="rv7dfo"
http://localhost:16686
```

At this stage, the Jaeger UI should load, but there will be no traces yet.

---

# 7. Install OpenTelemetry Collector ARM64 Package

Inside the VM:

```bash id="mwklru"
cd /tmp

OTEL_VERSION=0.154.0

sudo apt-get update
sudo apt-get -y install wget

wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTEL_VERSION}/otelcol_${OTEL_VERSION}_linux_arm64.deb

sudo dpkg -i otelcol_${OTEL_VERSION}_linux_arm64.deb
```

Verify:

```bash id="guz8u2"
/usr/bin/otelcol --version
sudo systemctl status otelcol --no-pager
```

The package installs the Collector as a systemd service.

Default config location:

```text id="b1b0db"
/etc/otelcol/config.yaml
```

Repository config location:

```text id="q5ol5x"
otel/otelcol-config.yaml
```

---

# 8. Configure OpenTelemetry Collector

Edit the Collector config:

```bash id="zlfhzt"
sudo nano /etc/otelcol/config.yaml
```

Use this full config:

```yaml id="5mp78d"
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 127.0.0.1:4317
      http:
        endpoint: 127.0.0.1:4318

processors:
  batch:

exporters:
  debug:
    verbosity: detailed

  otlp/jaeger:
    endpoint: 127.0.0.1:14317
    tls:
      insecure: true

service:
  telemetry:
    metrics:
      readers:
        - pull:
            exporter:
              prometheus:
                host: 127.0.0.1
                port: 8889

  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [debug, otlp/jaeger]
```

## Collector Pipeline Explanation

```yaml id="224ahx"
receivers:
  otlp:
```

The Collector receives telemetry from the Flask app using OTLP.

```yaml id="bm0x6a"
processors:
  batch:
```

The Collector batches telemetry before export.

```yaml id="4hv7h4"
exporters:
  debug:
  otlp/jaeger:
```

The Collector prints received spans to logs using the debug exporter and forwards traces to Jaeger using OTLP/gRPC.

```yaml id="mrv9od"
service:
  pipelines:
    traces:
```

The traces pipeline connects receiver, processor, and exporters.

---

# 9. OpenTelemetry Collector Port Design

The Collector receives telemetry from applications on the standard OTLP ports:

```text id="3srr3m"
Collector OTLP/gRPC: 127.0.0.1:4317
Collector OTLP/HTTP: 127.0.0.1:4318
```

The Collector forwards traces to Jaeger:

```text id="ur2lbp"
Collector -> Jaeger OTLP/gRPC: 127.0.0.1:14317
```

The Collector exposes its own internal Prometheus metrics on:

```text id="rovlop"
127.0.0.1:8889
```

This is intentionally set to `8889` to avoid conflicting with Jaeger’s internal metrics endpoint on `8888`.

---

# 10. Restart and Verify Collector

Restart Collector:

```bash id="qnxjvk"
sudo systemctl restart otelcol
```

Check status:

```bash id="wcmdfo"
sudo systemctl status otelcol --no-pager
```

Check logs:

```bash id="wlhr48"
sudo journalctl -u otelcol -n 100 --no-pager
```

Check ports:

```bash id="qhs5ak"
sudo ss -tulpn | egrep '16686|4317|4318|14317|14318|8888|8889'
```

Expected:

```text id="8wc36s"
0.0.0.0:16686       Jaeger UI
127.0.0.1:14317     Jaeger OTLP/gRPC receiver
127.0.0.1:14318     Jaeger OTLP/HTTP receiver
127.0.0.1:4317      OpenTelemetry Collector OTLP/gRPC receiver
127.0.0.1:4318      OpenTelemetry Collector OTLP/HTTP receiver
127.0.0.1:8888      Jaeger internal metrics
127.0.0.1:8889      OpenTelemetry Collector internal metrics
```

Test Collector internal metrics:

```bash id="rh1fyl"
curl -i http://127.0.0.1:8889/metrics | head
```

---

# 11. Troubleshooting

## Problem: OpenTelemetry Collector Fails on Port 8888

Example error:

```text id="x1bucx"
Error: failed to create meter provider:
binding address localhost:8888 for Prometheus exporter:
listen tcp 127.0.0.1:8888: bind: address already in use
```

Cause:

```text id="xk9l0b"
Jaeger v2 and OpenTelemetry Collector both try to expose internal Prometheus metrics on port 8888.
```

Fix:

Move the OpenTelemetry Collector internal metrics endpoint to port `8889`:

```yaml id="rfvj1s"
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

Then restart:

```bash id="0fu3l8"
sudo systemctl restart otelcol
```

Confirm:

```bash id="jha0hg"
sudo ss -tulpn | egrep '8888|8889'
```

Expected:

```text id="ddtw8r"
127.0.0.1:8888      Jaeger internal metrics
127.0.0.1:8889      OpenTelemetry Collector internal metrics
```

---

## Problem: Jaeger UI Does Not Load from Mac

Check inside VM:

```bash id="xekjfu"
curl -i http://127.0.0.1:16686
```

Check service:

```bash id="1qiydg"
sudo systemctl status jaeger --no-pager
```

Check port:

```bash id="mket3b"
sudo ss -tulpn | grep ':16686'
```

Expected:

```text id="osq7g9"
0.0.0.0:16686
```

If it works inside the VM but not from Mac, check the Vagrant port forwarding:

```ruby id="6tva1o"
config.vm.network "forwarded_port", guest: 16686, host: 16686
```

Then reload:

```bash id="3gjbt8"
vagrant reload
```

---

## Problem: Collector Running but No Traces in Jaeger

Check that the Collector can forward to Jaeger:

```bash id="j1o0zn"
sudo ss -tulpn | grep ':14317'
sudo systemctl status jaeger --no-pager
```

Check Collector logs:

```bash id="2o9ens"
sudo journalctl -u otelcol -n 100 --no-pager
```

Check Jaeger logs:

```bash id="x5kkhw"
sudo journalctl -u jaeger -n 100 --no-pager
```

Verify Collector config:

```bash id="mfo4k9"
sudo grep -Rni "14317\|4317\|otlp/jaeger\|debug" /etc/otelcol/config.yaml
```

Expected:

```text id="64hsxv"
endpoint: 127.0.0.1:4317
endpoint: 127.0.0.1:14317
otlp/jaeger
debug
```

---

# 12. Useful Commands

## Service Status

```bash id="zeotjq"
sudo systemctl status jaeger --no-pager
sudo systemctl status otelcol --no-pager
```

## Recent Logs

```bash id="olpr9h"
sudo journalctl -u jaeger -n 100 --no-pager
sudo journalctl -u otelcol -n 100 --no-pager
```

## Follow Logs

```bash id="8jkbw1"
sudo journalctl -u jaeger -f
sudo journalctl -u otelcol -f
```

## Check Ports

```bash id="3x5g8h"
sudo ss -tulpn | egrep '16686|4317|4318|14317|14318|8888|8889'
```

## Test Jaeger UI

```bash id="a2e8ec"
curl -i http://127.0.0.1:16686
```

From Mac:

```text id="ggrr4o"
http://localhost:16686
```

## Test Collector Metrics

```bash id="thhruh"
curl -i http://127.0.0.1:8889/metrics | head
```

---

# 13. Final Working State

This phase is complete when:

```text id="a60bn6"
[ ] Jaeger systemd service is active
[ ] OpenTelemetry Collector systemd service is active
[ ] Jaeger UI opens from Mac at http://localhost:16686
[ ] Collector listens on 127.0.0.1:4317
[ ] Collector listens on 127.0.0.1:4318
[ ] Jaeger listens on 127.0.0.1:14317
[ ] Jaeger listens on 127.0.0.1:14318
[ ] Jaeger internal metrics are exposed on 127.0.0.1:8888
[ ] Collector internal metrics are exposed on 127.0.0.1:8889
```

Working telemetry path:

```text id="1bxyim"
Flask app
  -> 127.0.0.1:4317
  -> OpenTelemetry Collector
  -> 127.0.0.1:14317
  -> Jaeger
  -> Jaeger UI at http://localhost:16686
```

At this point, Jaeger and the Collector are ready. The next step is Python auto-instrumentation for the Flask app.
