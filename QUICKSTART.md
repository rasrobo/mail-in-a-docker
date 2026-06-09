# Quickstart

Get a working Mail-in-a-Box in Docker in minutes.

```bash
# 1. Clone
git clone https://github.com/rasrobo/mail-in-a-docker
cd mail-in-a-docker

# 2. Configure
cp .env.example .env
echo "PRIMARY_HOSTNAME=mail.example.com" >> .env

# 3. Build
docker compose build

# 4. Start container
docker compose up -d

# 5. Install MIAB
docker exec miad bash /install.sh mail.example.com

# 6. Start services
docker exec miad bash -c '
  systemctl daemon-reload
  for svc in postfix dovecot nginx php8.1-fpm opendkim opendmarc nsd named fail2ban; do
    systemctl enable --now $svc 2>/dev/null || true
  done
'

# 7. Install host SNIProxy
apt-get install -y sniproxy
systemctl enable --now sniproxy

# 8. Create admin user
docker exec miad python3 << PYEOF
import sys
sys.path.insert(0, "/opt/mailinabox")
sys.path.insert(0, "/opt/mailinabox/management")
import mailconfig
env = {"STORAGE_ROOT": "/home/user-data", "PRIMARY_HOSTNAME": "mail.example.com", "PUBLIC_IP": "SERVER_IP", "PUBLIC_IPV6": ""}
mailconfig.add_mail_user("admin@example.com", "changeme", "admin", env)
PYEOF

# 9. Verify
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:810/
# → 200

# 10. Open in browser
# http://mail.example.com:810/
# or with SNIProxy: http://mail.example.com/
```

## What's next?

- Set up DNS records (see [DNS requirements](README.md#dns-requirements))
- Add domains and mailboxes through the admin panel
- Configure your mail client (IMAP: port 993, SMTP: port 587)
- For full walkthrough → [INSTALL.md](INSTALL.md)
- For troubleshooting → [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
