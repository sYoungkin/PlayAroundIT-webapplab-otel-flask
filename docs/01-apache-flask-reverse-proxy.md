# 01 — Apache + Flask Reverse Proxy Setup

## Goal

Set up a small Flask web application behind Apache2 using Apache as a reverse proxy.

The target architecture is:

```text
Mac browser / curl
  -> http://webapplab.test:8080
  -> Vagrant port forward: host 8080 -> guest 80
  -> Apache2 VirtualHost
  -> ProxyPass /app/ -> http://127.0.0.1:5000/
  -> Flask application
```

This creates a realistic web application pattern:

```text
Client
  -> Web server / reverse proxy
  -> Backend application
```

Apache handles the external HTTP entry point. Flask runs as a backend service on localhost inside the VM.

---

# 1. Vagrant Port Forwarding

The VM exposes Apache port `80` to the Mac host on port `8080`.

In the `Vagrantfile`:

```ruby
config.vm.network "forwarded_port", guest: 80, host: 8080
```

This means:

```text
Mac host: http://localhost:8080
  -> forwarded to VM: http://127.0.0.1:80
```

The lab uses the hostname:

```text
webapplab.test
```

On the Mac host, add this to `/etc/hosts`:

```text
127.0.0.1 webapplab.test
```

Then the browser URL becomes:

```text
http://webapplab.test:8080
```

Important: `/etc/hosts` maps names to IP addresses, not ports. The `:8080` port is still required because Vagrant forwards Mac port `8080` to VM port `80`.

---

# 2. Install Apache2

Inside the Ubuntu VM:

```bash
sudo apt update
sudo apt install -y apache2
```

Check Apache:

```bash
sudo systemctl status apache2 --no-pager
```

Test locally inside the VM:

```bash
curl -i http://127.0.0.1
```

Test from the Mac host:

```bash
curl -i http://webapplab.test:8080
```

At this point, Apache should return the default Apache page.

---

# 3. Create the Apache Web Root

Create a dedicated web root for the lab:

```bash
sudo mkdir -p /var/www/webapplab
echo '<h1>webapplab Apache front page</h1>' | sudo tee /var/www/webapplab/index.html
sudo chown -R www-data:www-data /var/www/webapplab
```

This static page is served by Apache directly at:

```text
http://webapplab.test:8080/
```

The Flask application will later be available under:

```text
http://webapplab.test:8080/app/
```

---

# 4. Create Apache VirtualHost Config

Create exactly one Apache site config:

```bash
sudo nano /etc/apache2/sites-available/webapplab.conf
```

Use this config:

```apache
<VirtualHost *:80>
    ServerName webapplab.test
    ServerAdmin webmaster@localhost

    DocumentRoot /var/www/webapplab

    ErrorLog ${APACHE_LOG_DIR}/webapplab-error.log

    LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\" vhost=%v host=\"%{Host}i\" duration_us=%D request_id=\"%{X-Request-ID}o\"" webapplab_combined
    CustomLog ${APACHE_LOG_DIR}/webapplab-access.log webapplab_combined

    ProxyPreserveHost On

    ProxyPass "/app/" "http://127.0.0.1:5000/"
    ProxyPassReverse "/app/" "http://127.0.0.1:5000/"
</VirtualHost>
```

Runtime location:

```text
/etc/apache2/sites-available/webapplab.conf
```

Repository location:

```text
apache/webapplab.conf
```

---

# 5. Enable Apache Proxy Modules and Site

Enable Apache reverse proxy modules:

```bash
sudo a2enmod proxy proxy_http
```

Enable the `webapplab` site:

```bash
sudo a2ensite webapplab.conf
```

Disable the default Apache site to avoid vhost confusion:

```bash
sudo a2dissite 000-default.conf
```

Validate Apache config:

```bash
sudo apache2ctl configtest
```

Expected:

```text
Syntax OK
```

Reload Apache:

```bash
sudo systemctl reload apache2
```

Check enabled sites:

```bash
ls -l /etc/apache2/sites-enabled/
```

Expected:

```text
webapplab.conf -> ../sites-available/webapplab.conf
```

Check active Apache vhosts:

```bash
sudo apache2ctl -S
```

Expected:

```text
*:80 webapplab.test
```

Verify the active enabled config contains the proxy rules:

```bash
sudo grep -Rni "ServerName\|DocumentRoot\|ProxyPass\|ProxyPassReverse" /etc/apache2/sites-enabled/
```

Expected:

```text
ServerName webapplab.test
DocumentRoot /var/www/webapplab
ProxyPass "/app/" "http://127.0.0.1:5000/"
ProxyPassReverse "/app/" "http://127.0.0.1:5000/"
```

---

# 6. Install Python and Flask

Install Python virtual environment support:

```bash
sudo apt install -y python3-venv
```

Create the Flask project directory:

```bash
mkdir -p /home/vagrant/flask-lab
cd /home/vagrant/flask-lab
```

Create and activate a Python virtual environment:

```bash
python3 -m venv venv
source venv/bin/activate
```

Install Flask:

```bash
pip install --upgrade pip
pip install flask
```

Create a log directory for the Flask application:

```bash
sudo mkdir -p /var/log/webapplab
sudo chown $USER:$USER /var/log/webapplab
```

Runtime app path:

```text
/home/vagrant/flask-lab/app.py
```

Repository app path:

```text
app/app.py
```

---

# 7. Run the Flask App Manually

From inside the VM:

```bash
cd /home/vagrant/flask-lab
source venv/bin/activate
python app.py
```

Expected:

```text
Running on http://127.0.0.1:5000
```

The Flask app is intentionally run manually during development so it can be stopped, edited, and restarted easily.

---

# 8. Test the Flask App Directly

Inside the VM, test Flask directly without Apache:

```bash
curl -i http://127.0.0.1:5000/
curl -i http://127.0.0.1:5000/api/health
```

Expected:

```text
HTTP/1.1 200 OK
```

If this fails, the issue is with Flask or the Python environment, not Apache.

---

# 9. Test Apache Reverse Proxy Inside the VM

Inside the VM:

```bash
curl -i -H "Host: webapplab.test" http://127.0.0.1/app/
curl -i -H "Host: webapplab.test" http://127.0.0.1/app/api/health
```

Expected:

```text
HTTP/1.1 200 OK
```

This verifies:

```text
Apache receives the request
  -> Apache matches the webapplab.test vhost
  -> Apache applies ProxyPass /app/
  -> Apache forwards to Flask on 127.0.0.1:5000
```

---

# 10. Test End-to-End from the Mac Host

From the Mac host:

```bash
curl -i http://webapplab.test:8080/
curl -i http://webapplab.test:8080/app/
curl -i http://webapplab.test:8080/app/api/health
```

Browser URLs:

```text
http://webapplab.test:8080/
http://webapplab.test:8080/app/
http://webapplab.test:8080/app/api/health
```

Expected:

```text
HTTP/1.1 200 OK
```

---

# 11. Important Logs

## Apache Access Log

```bash
sudo tail -f /var/log/apache2/webapplab-access.log
```

Shows:

```text
client IP
request path
HTTP status
user agent
duration_us
request_id
```

## Apache Error Log

```bash
sudo tail -f /var/log/apache2/webapplab-error.log
```

Useful for:

```text
proxy errors
backend unavailable errors
Apache config/runtime errors
```

## Flask App JSON Log

```bash
tail -f /var/log/webapplab/app.jsonl
```

Shows structured application logs generated by the Flask app.

## Flask Foreground Terminal

When the app is run with:

```bash
python app.py
```

the terminal shows:

```text
Flask startup messages
Flask request logs
Python exceptions
stack traces
```

---

# 12. Useful Health Checks

## Check Apache

```bash
sudo systemctl status apache2 --no-pager
```

## Check Flask Port

```bash
sudo ss -tulpn | grep ':5000'
```

Expected if Flask is running:

```text
127.0.0.1:5000
```

## Check Apache Port

```bash
sudo ss -tulpn | grep ':80'
```

Expected:

```text
0.0.0.0:80
```

## Check Apache Modules

```bash
apache2ctl -M | grep proxy
```

Expected:

```text
proxy_module
proxy_http_module
```

---

# 13. Status Code Interpretation

## 200 OK

Everything worked.

```text
Client
  -> Apache
  -> Flask
  -> response returned successfully
```

## 404 Not Found

Possible causes:

```text
wrong URL path
ProxyPass rule not active
wrong Apache vhost
Flask route does not exist
```

How to distinguish:

```text
Apache access log shows 404, Flask terminal shows nothing
  -> Apache did not proxy the request

Flask terminal shows request and 404
  -> Flask received the request, but route does not exist
```

## 500 Internal Server Error

Possible cause:

```text
Flask route executed but returned or raised an application error
```

Check:

```bash
tail -f /var/log/webapplab/app.jsonl
```

Also check the Flask foreground terminal.

## 503 Service Unavailable

Possible cause:

```text
Apache reverse proxy is working,
but the Flask backend is unavailable.
```

Most common cause:

```text
Flask is not running on 127.0.0.1:5000
```

Check:

```bash
sudo ss -tulpn | grep ':5000'
curl -i http://127.0.0.1:5000/api/health
sudo tail -n 50 /var/log/apache2/webapplab-error.log
```

Typical Apache error log:

```text
failed to make connection to backend: 127.0.0.1
attempt to connect to 127.0.0.1:5000 failed
```

---

# 14. Troubleshooting Decision Tree

```text
1. Does Flask work directly?

   curl -i http://127.0.0.1:5000/api/health

   No:
     Start or fix Flask.

   Yes:
     Continue.

2. Does Apache proxy work inside the VM?

   curl -i -H "Host: webapplab.test" http://127.0.0.1/app/api/health

   No:
     Check Apache vhost, ProxyPass, modules, and logs.

   Yes:
     Continue.

3. Does Mac host access work?

   curl -i http://webapplab.test:8080/app/api/health

   No:
     Check Vagrant port forwarding and Mac /etc/hosts.

   Yes:
     Application path is healthy.
```

---

# 15. Current Working Commands

Start Flask manually:

```bash
cd /home/vagrant/flask-lab
source venv/bin/activate
python app.py
```

Flask direct test:

```bash
curl -i http://127.0.0.1:5000/api/health
```

Apache proxy test inside VM:

```bash
curl -i -H "Host: webapplab.test" http://127.0.0.1/app/api/health
```

End-to-end Mac test:

```bash
curl -i http://webapplab.test:8080/app/api/health
```

Watch Apache access log:

```bash
sudo tail -f /var/log/apache2/webapplab-access.log
```

Watch Apache error log:

```bash
sudo tail -f /var/log/apache2/webapplab-error.log
```

Watch Flask JSON log:

```bash
tail -f /var/log/webapplab/app.jsonl
```

---

# 16. Final Working State

This phase is complete when:

```text
[ ] Apache is running
[ ] Flask is running on 127.0.0.1:5000
[ ] Apache vhost webapplab.test is active
[ ] Apache proxy modules are enabled
[ ] /app/ is proxied to Flask
[ ] http://webapplab.test:8080/app/api/health returns 200
[ ] Apache access log records requests
[ ] Flask app log records requests
```
