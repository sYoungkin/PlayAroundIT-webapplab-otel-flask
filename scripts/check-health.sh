curl -i http://webapplab.test:8080/app/api/health
curl -i http://127.0.0.1:5000/api/health
sudo systemctl status jaeger --no-pager
sudo systemctl status otelcol --no-pager
sudo ss -tulpn | egrep '80|5000|4317|4318|14317|14318|16686|8888|8889'