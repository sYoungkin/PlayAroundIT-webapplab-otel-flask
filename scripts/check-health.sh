#!/usr/bin/env bash

set -u

FAILS=0

APP_HOST="${APP_HOST:-webapplab.test}"
FLASK_DIR="${FLASK_DIR:-/home/vagrant/flask-lab}"

APACHE_HEALTH_URL="http://127.0.0.1/"
APACHE_PROXY_HEALTH_URL="http://127.0.0.1/app/api/health"
FLASK_HEALTH_URL="http://127.0.0.1:5000/api/health"
JAEGER_UI_URL="http://127.0.0.1:16686"
OTELCOL_METRICS_URL="http://127.0.0.1:8889/metrics"

HOST_HEADER="Host: ${APP_HOST}"

line() {
printf '%s\n' "------------------------------------------------------------"
}

section() {
printf '\n'
line
printf '%s\n' "$1"
line
}

ok() {
printf '[OK]   %s\n' "$1"
}

warn() {
printf '[WARN] %s\n' "$1"
}

fail() {
printf '[FAIL] %s\n' "$1"
FAILS=$((FAILS + 1))
}

info() {
printf '[INFO] %s\n' "$1"
}

check_command() {
local cmd="$1"

if command -v "$cmd" >/dev/null 2>&1; then
ok "Command available: ${cmd}"
else
fail "Command missing: ${cmd}"
fi
}

check_service() {
local service="$1"

if systemctl is-active --quiet "$service"; then
ok "Service active: ${service}"
else
fail "Service not active: ${service}"
systemctl status "$service" --no-pager 2>/dev/null | sed 's/^/       /' | head -n 12
fi
}

check_port() {
local label="$1"
local port="$2"

if ss -ltn | grep -Eq "[:.]${port}[[:space:]]"; then
ok "${label} listening on port ${port}"
else
fail "${label} not listening on port ${port}"
fi
}

http_check() {
local label="$1"
local url="$2"
local expected_code="$3"
local header="${4:-}"

local body_file
local err_file
local code

body_file="$(mktemp)"
err_file="$(mktemp)"

if [[ -n "$header" ]]; then
code="$(curl -sS --max-time 5 -o "$body_file" -w "%{http_code}" -H "$header" "$url" 2>"$err_file" || true)"
else
code="$(curl -sS --max-time 5 -o "$body_file" -w "%{http_code}" "$url" 2>"$err_file" || true)"
fi

if [[ "$code" == "$expected_code" ]]; then
ok "${label}: HTTP ${code}"
else
fail "${label}: expected HTTP ${expected_code}, got HTTP ${code}"
if [[ -s "$err_file" ]]; then
sed 's/^/       curl error: /' "$err_file"
fi
if [[ -s "$body_file" ]]; then
printf '       response preview: '
head -c 200 "$body_file" | tr '\n' ' '
printf '\n'
fi
fi

rm -f "$body_file" "$err_file"
}

check_file() {
local label="$1"
local path="$2"

if [[ -f "$path" ]]; then
ok "${label}: ${path}"
else
fail "${label} missing: ${path}"
fi
}

check_dir() {
local label="$1"
local path="$2"

if [[ -d "$path" ]]; then
ok "${label}: ${path}"
else
fail "${label} missing: ${path}"
fi
}

print_endpoint_summary() {
  printf '\n'
  printf 'Useful endpoints:\n\n'

  printf '  Inside VM:\n'
  printf '    Apache static via vhost:\n'
  printf '      curl -i -H "%s" http://127.0.0.1/\n\n' "$HOST_HEADER"

  printf '    Apache -> Flask proxy health:\n'
  printf '      curl -i -H "%s" http://127.0.0.1/app/api/health\n\n' "$HOST_HEADER"

  printf '    Flask direct:\n'
  printf '      curl -i http://127.0.0.1:5000/api/health\n\n'

  printf '    Jaeger UI:\n'
  printf '      http://127.0.0.1:16686\n\n'

  printf '    OTel Collector metrics:\n'
  printf '      http://127.0.0.1:8889/metrics\n\n'

  printf '  From Mac host:\n'
  printf '    Apache static:\n'
  printf '      http://%s:8080/\n\n' "$APP_HOST"

  printf '    Flask through Apache:\n'
  printf '      http://%s:8080/app/api/health\n\n' "$APP_HOST"

  printf '    Jaeger UI:\n'
  printf '      http://localhost:16686\n\n'
}

print_log_summary() {
  printf '\n'
  printf 'Useful logs:\n\n'

  printf '  Apache access log:\n'
  printf '    sudo tail -f /var/log/apache2/webapplab-access.log\n\n'

  printf '  Apache error log:\n'
  printf '    sudo tail -f /var/log/apache2/webapplab-error.log\n\n'

  printf '  Flask JSON app log:\n'
  printf '    tail -f /var/log/webapplab/app.jsonl\n\n'

  printf '  Jaeger logs:\n'
  printf '    sudo journalctl -u jaeger -f\n\n'

  printf '  OpenTelemetry Collector logs:\n'
  printf '    sudo journalctl -u otelcol -f\n\n'
}

print_next_steps_if_failed() {
  printf '\n'
  printf 'Troubleshooting hints:\n\n'

  printf '  If Flask direct fails:\n'
  printf '    cd %s\n' "$FLASK_DIR"
  printf '    source venv/bin/activate\n'
  printf '    python app.py\n\n'

  printf '  If Apache proxy returns 503:\n'
  printf '    Flask is probably not running on 127.0.0.1:5000.\n\n'

  printf '  If Apache proxy returns 404:\n'
  printf '    Check active vhost and ProxyPass:\n'
  printf '      sudo apache2ctl -S\n'
  printf '      sudo grep -Rni "ProxyPass\\|ServerName" /etc/apache2/sites-enabled/\n\n'

  printf '  If Jaeger UI fails:\n'
  printf '    sudo systemctl status jaeger --no-pager\n'
  printf '    sudo journalctl -u jaeger -n 100 --no-pager\n\n'

  printf '  If Collector fails:\n'
  printf '    sudo systemctl status otelcol --no-pager\n'
  printf '    sudo journalctl -u otelcol -n 100 --no-pager\n\n'
}

printf '\n'
printf '%s\n' "WebAppLab Health Check"
printf '%s\n' "Host header: ${APP_HOST}"
printf '%s\n' "Flask dir:   ${FLASK_DIR}"
printf '%s\n' "Timestamp:   $(date)"
printf '\n'

section "1. Required Commands"
check_command curl
check_command ss
check_command systemctl
check_command apache2ctl

section "2. Service Status"
check_service apache2
check_service jaeger
check_service otelcol

section "3. Runtime Files and Directories"
check_dir "Flask project directory" "$FLASK_DIR"
check_file "Flask app" "${FLASK_DIR}/app.py"
check_file "Apache vhost config" "/etc/apache2/sites-available/webapplab.conf"
check_file "Jaeger config" "/etc/jaeger/config.yaml"
check_file "OpenTelemetry Collector config" "/etc/otelcol/config.yaml"

section "4. Port Checks"
check_port "Apache" 80
check_port "Flask app" 5000
check_port "OTel Collector OTLP/gRPC" 4317
check_port "OTel Collector OTLP/HTTP" 4318
check_port "Jaeger OTLP/gRPC" 14317
check_port "Jaeger OTLP/HTTP" 14318
check_port "Jaeger UI" 16686
check_port "Jaeger internal metrics" 8888
check_port "OTel Collector internal metrics" 8889

section "5. HTTP Endpoint Checks"
http_check "Flask direct health" "$FLASK_HEALTH_URL" "200"
http_check "Apache static via vhost" "$APACHE_HEALTH_URL" "200" "$HOST_HEADER"
http_check "Apache reverse proxy to Flask" "$APACHE_PROXY_HEALTH_URL" "200" "$HOST_HEADER"
http_check "Jaeger UI local" "$JAEGER_UI_URL" "200"
http_check "OTel Collector internal metrics" "$OTELCOL_METRICS_URL" "200"

section "6. Apache Configuration Checks"
if apache2ctl -M 2>/dev/null | grep -q "proxy_module"; then
ok "Apache module enabled: proxy_module"
else
fail "Apache module missing: proxy_module"
fi

if apache2ctl -M 2>/dev/null | grep -q "proxy_http_module"; then
ok "Apache module enabled: proxy_http_module"
else
fail "Apache module missing: proxy_http_module"
fi

if sudo grep -Rni 'ServerName webapplab.test' /etc/apache2/sites-enabled/ >/dev/null 2>&1; then
ok "Apache enabled config contains ServerName webapplab.test"
else
fail "Apache enabled config missing ServerName webapplab.test"
fi

if sudo grep -Rni 'ProxyPass "/app/" "http://127.0.0.1:5000/"' /etc/apache2/sites-enabled/ >/dev/null 2>&1; then
ok "Apache enabled config contains expected ProxyPass"
else
fail "Apache enabled config missing expected ProxyPass"
fi

section "7. Endpoint Reference"
print_endpoint_summary

section "8. Log Reference"
print_log_summary

section "9. Result"

if [[ "$FAILS" -eq 0 ]]; then
ok "WebAppLab health check passed with no failures."
exit 0
else
fail "WebAppLab health check completed with ${FAILS} failure(s)."
print_next_steps_if_failed
exit 1
fi
