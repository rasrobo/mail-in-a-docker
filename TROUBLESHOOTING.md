# Troubleshooting

## DNS resolution breaks after setup-dns.sh

The `setup-dns.sh` script installs BIND9 and NSD, which may conflict with `systemd-resolved`.

**Fix:** Stop systemd-resolved and set a fallback nameserver:

```bash
systemctl stop systemd-resolved
systemctl disable systemd-resolved
echo "nameserver 8.8.8.8" > /etc/resolv.conf
```

## Container fails to start

Check for port conflicts on the host:

```bash
ss -tulpn | grep -E ":(25|53|80|443|465|587|993|995) "
```

If ports are in use, stop the conflicting service or adjust the port mappings in `docker-compose.yaml`.

## Port 53 (DNS) already in use

The container needs port 53 for authoritative DNS. If `systemd-resolved` or another DNS server is using it:

```bash
systemctl stop systemd-resolved
systemctl disable systemd-resolved
```

## Certificate issuance fails

Let's Encrypt requires port 80 to be reachable from the internet. Verify:

```bash
# From outside your network
curl -I http://mail.example.com/.well-known/acme-challenge/test
```

If your server is behind NAT or a firewall, ensure port 80 is forwarded.

## Mail rejected — missing SPF/DKIM/DMARC

After setup, check the admin panel for the DKIM record to add to your DNS. Common issues:

- **SPF** missing: Add `v=spf1 mx a:mail.example.com -all` as a TXT record
- **DKIM** missing: Copy the DKIM record from the admin panel → System → DNS
- **DMARC** missing: Add `v=DMARC1; p=reject; rua=mailto:admin@example.com`
- **PTR/rDNS** not set: Request from your VPS provider

## Reverse DNS (PTR) mismatch

Many mail servers reject mail if the SMTP banner hostname doesn't match the reverse DNS of the sending IP.

- Request PTR record from your VPS provider: `SERVER_IP` → `mail.example.com`
- Verify: `dig -x SERVER_IP`

## Docker installed via snap

The snap version of Docker has restricted access to the host filesystem and won't work.

**Fix:** Remove snap Docker and install the official version:

```bash
snap remove docker
apt-get install -y docker-ce docker-ce-cli containerd.io
```

## Container hostname mismatch

If the container hostname doesn't match the DNS A record for your domain, mail delivery may fail.

```bash
docker exec miad hostname -f
# Should output: mail.example.com
```

If incorrect, the install.sh script should set it. You can also set it manually:

```bash
docker exec miad hostname mail.example.com
```

## Firewall interference

UFW or nftables may block mail ports. Mail-in-a-Box disables the firewall during setup. Re-enable it afterward with the right rules:

```bash
ufw allow 25/tcp
ufw allow 53/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 465/tcp
ufw allow 587/tcp
ufw allow 993/tcp
ufw allow 995/tcp
ufw enable
```

## Permissions or capability problems inside Docker

The container runs with `privileged: true` and `SYS_ADMIN` capability to manage systemd services. Some hosts may restrict these capabilities (e.g., in Kubernetes or certain VPS environments). If services fail to start, check:

```bash
docker exec miad journalctl -xe --no-pager | tail -30
```

## DNS changes not reflected

MIAB DNS changes (adding domains via the admin panel) are not automatically pushed to the host's NSD/BIND9. Run the setup script to sync:

```bash
./setup-dns.sh
```

(An inotify-based auto-sync is planned for future releases.)

## SNIProxy not routing correctly

SNIProxy inspects the TLS SNI header to route traffic. If you're testing with curl, ensure you send the hostname:

```bash
curl -H "Host: mail.example.com" http://127.0.0.1/
```

For HTTPS, SNIProxy relies on the TLS handshake — use the domain directly.

## Checking logs

```bash
# Container logs
docker logs miad --tail 50

# Postfix logs
docker exec miad tail -f /var/log/mail.log

# All services
docker exec miad systemctl list-units --type=service --state=running
```

## Still stuck?

Open an issue at [github.com/rasrobo/mail-in-a-docker/issues](https://github.com/rasrobo/mail-in-a-docker/issues) with:

- Output of `docker logs miad --tail 50`
- Output of `docker exec miad systemctl list-units --type=service --state=failed`
- Host OS version and Docker version
- Any relevant firewall or DNS configuration
