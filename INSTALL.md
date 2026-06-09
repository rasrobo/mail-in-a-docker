# Installation Guide

## Prerequisites

- **Ubuntu 22.04 (Jammy)** server (bare metal or VPS) with root access
- **Public IPv4 address** with DNS pointing to it
- **Official Docker** installed (not snap)

### Docker Installation

```bash
# Remove any existing Docker packages
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  apt-get remove -y $pkg 2>/dev/null || true
done

# Install dependencies
apt-get update
apt-get install -y ca-certificates curl

# Add Docker's official GPG key and repository
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" > /etc/apt/sources.list.d/docker.list

# Install Docker
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
docker --version
```

## Step 1 — Clone and configure

```bash
git clone https://github.com/rasrobo/mail-in-a-docker
cd mail-in-a-docker
cp .env.example .env
```

Edit `.env` and set your primary mail hostname:

```bash
PRIMARY_HOSTNAME=mail.example.com
```

## Step 2 — Build the Docker image

```bash
docker compose build
```

This installs all dependencies inside the container: Postfix, Dovecot, nginx, PHP 8.1, BIND9, NSD, SpamAssassin, OpenDKIM, OpenDMARC, and more. It takes 3–5 minutes.

## Step 3 — Start the container

```bash
docker compose up -d
```

Verify it's running:

```bash
docker ps | grep miad
```

## Step 4 — Install Mail-in-a-Box

```bash
# The install.sh script clones MIAB v68 and runs the full setup
docker exec miad bash /install.sh mail.example.com
```

This step:
- Clones Mail-in-a-Box v68 inside the container
- Patches MIAB for Docker compatibility (container-appropriate service management, PHP 8.1, etc.)
- Runs the full MIAB setup: Postfix, Dovecot, nginx, DKIM, DMARC, SpamAssassin
- Disables Nextcloud (not supported in this container build)
- Generates SSL certificates and DNSSEC keys

The install takes 5-10 minutes depending on your server.

## Step 5 — Start the management daemon

After install completes, start all services:

```bash
docker exec miad bash -c '
  systemctl daemon-reload
  for svc in postfix dovecot nginx php8.1-fpm opendkim opendmarc nsd named fail2ban spampd; do
    systemctl enable --now $svc 2>/dev/null || true
  done
'
```

## Step 6 — Set up SNIProxy (host)

SNIProxy allows the container to share ports 80/443 with other services on the host.

```bash
apt-get install -y sniproxy

cat > /etc/sniproxy.conf << 'EOF'
user daemon
pidfile /var/run/sniproxy.pid

error_log {
    syslog daemon
    priority notice
}

listen 80 {
    proto http
    table http_hosts
    fallback 127.0.0.1:810
}

listen 443 {
    proto tls
    table https_hosts
    fallback 127.0.0.1:4413
}

table http_hosts {
    mta-sts\..* 127.0.0.1:810
}

table https_hosts {
    mta-sts\..* 127.0.0.1:4413
}
EOF

echo 'DAEMON_ARGS="-f"' > /etc/default/sniproxy
systemctl enable --now sniproxy
```

## Step 7 — Create your first admin user

```bash
docker exec miad python3 -c "
import sys
sys.path.insert(0, '/opt/mailinabox')
sys.path.insert(0, '/opt/mailinabox/management')
import mailconfig
env = {
    'STORAGE_ROOT': '/home/user-data',
    'PRIMARY_HOSTNAME': 'mail.example.com',
    'PUBLIC_IP': 'SERVER_PUBLIC_IP',
    'PUBLIC_IPV6': ''
}
mailconfig.add_mail_user('admin@example.com', 'YOUR_PASSWORD', 'admin', env)
print('User created')
"
```

Replace `SERVER_PUBLIC_IP` with your server's public IP and `YOUR_PASSWORD` with a strong password.

## Step 8 — Verify

```bash
# Check services
docker exec miad bash -c '
  for svc in postfix dovecot nginx nsd named; do
    systemctl is-active \$svc >/dev/null && echo \"✓ \$svc\" || echo \"✗ \$svc\"
  done
'

# Test admin panel
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:810/
# Should return 200
```

Open `http://mail.example.com:810/` in your browser to access the admin panel.

## Next steps

1. Add additional domains through the admin panel
2. Create mailboxes and aliases
3. Configure DNS SPF, DKIM, and DMARC records
4. Set up PTR/rDNS with your VPS provider
5. Configure firewall rules to restrict access
