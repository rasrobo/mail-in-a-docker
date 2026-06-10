# Installation Guide

## Prerequisites

- Ubuntu 22.04 (Jammy) server with root access
- Docker CE (official, not snap)
- A domain with DNS pointed at your server
- Ports 25, 53, 80, 443, 465, 587, 993, 995, 4190 reachable from the internet

## Step 1: Install Docker

```bash
# Run the setup script
chmod +x setup-official-docker.sh
./setup-official-docker.sh

# Verify
docker --version
docker compose version
```

## Step 2: Clone and configure

```bash
git clone https://github.com/rasrobo/mail-in-a-docker
cd mail-in-a-docker

# Configure your mail hostname and timezone
cp .env.example .env
# Edit .env and set PRIMARY_HOSTNAME to your mail domain
```

## Step 3: Build and start

```bash
docker compose build
docker compose up -d
```

## Step 4: Install Mail-in-a-Box

```bash
docker exec miad bash /install.sh mail.example.com
```

This clones Mail-in-a-Box v68, applies Docker-specific patches, and runs the MIAB installer inside the container. It takes 5-15 minutes.

## Step 5: Start services

```bash
docker exec miad bash -c '
  systemctl daemon-reload
  for svc in postfix dovecot nginx php8.1-fpm opendkim opendmarc nsd named fail2ban; do
    systemctl enable --now $svc 2>/dev/null || true
  done
'
```

## Step 6: Set up SNIProxy

```bash
apt-get install -y sniproxy
cp sniproxy.conf.example /etc/sniproxy.conf
echo 'DAEMON_ARGS="-f"' >> /etc/default/sniproxy
systemctl enable --now sniproxy
```

## Step 7: Create admin user

```bash
docker exec miad python3 << 'PYEOF'
import sys
sys.path.insert(0, "/opt/mailinabox")
sys.path.insert(0, "/opt/mailinabox/management")
import mailconfig
env = {
    "STORAGE_ROOT": "/home/user-data",
    "PRIMARY_HOSTNAME": "mail.example.com",
    "PUBLIC_IP": "SERVER_IP",
    "PUBLIC_IPV6": ""
}
mailconfig.add_mail_user("admin@example.com", "changeme", "admin", env)
PYEOF
```

## Step 8: Verify

```bash
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:810/
# → 200

docker exec miad /status-check.sh
# All ports should show listeners
```

## Step 9: Set up DNS

Configure your domain's DNS (see [DNS requirements](README.md#dns-requirements)) and request a PTR record from your VPS provider.

## Step 10: Access the admin panel

Open `https://mail.example.com/` or `http://mail.example.com:810/` in your browser.
