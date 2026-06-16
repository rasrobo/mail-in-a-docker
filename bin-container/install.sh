#!/bin/bash

if false; then
    # /usr/sbin/named -u bind -g

    # recursive dns at 127.0.0.1
    cp /etc/resolv.conf .
    sed -i "s/nameserver/# nameserver/" resolv.conf
    echo nameserver 127.0.0.1 >>resolv.conf
    cp resolv.conf /etc/resolv.conf

    # start named run as root
    sed -i "s/-u bind/-u root/" /etc/default/named
    cp /named.conf /etc/bind/named.conf
    systemctl enable --now named

    # systemctl status named.service
    # ping google.com
    # exit 0
fi

# exit 0

sudo systemctl enable --now ssh
hostname $1

# enable ipv6 for nsd to start properly
sudo git clone https://github.com/mail-in-a-box/mailinabox

cd mailinabox
git checkout v68

## START: Before install

/home/user-data/before-install.sh

sed -i "s/-u bind /-u root /" /mailinabox/setup/system.sh
sed -i "s/SSH_PORT=/SSH_PORT=22\#/" /mailinabox/setup/system.sh
sed -i "s/rm -f \/etc\/resolv.conf/echo rm -f \/etc\/resolv.conf || true/" /mailinabox/setup/system.sh
sed -i "s/echo \"nameserver 127.0.0.1/\#echo \"nameserver 127.0.0.1/" /mailinabox/setup/system.sh
#sed -i "s/\# Get a/echo \$@; \# Get a/" /mailinabox/setup/functions.sh
sed -i "s/hide_output service \$1 restart/return \#hide_output service \$1 restart/" /mailinabox/setup/functions.sh
sed -i "s/DEBIAN_FRONTEND=noninteractive hide_output apt-get -y/DEBIAN_FRONTEND=noninteractive hide_output apt-get --no-install-recommends -y/" /mailinabox/setup/functions.sh

# Use PHP 8.1
sed -i "s/PHP_VER=8.0/PHP_VER=8.1;DISABLE_FIREWALL=0/" /mailinabox/setup/functions.sh
sed -i "s/php8.0-fpm/php8.1-fpm/" /mailinabox/conf/nginx-top.conf
sed -i "s/php8.0-fpm/php8.1-fpm/" /mailinabox/tools/owncloud-restore.sh
sed -i "s/php8.0-fpm/php8.1-fpm/" /mailinabox/management/backup.py

# disable nextcloud
echo "- Disabling nextcloud installation"
sed -i "s/source setup\/nextcloud.sh/# source setup\/nextcloud.sh/" /mailinabox/setup/start.sh

## END: Before install

# shift nginx ports
# sed -i "s/listen 80;/listen 810;/" /mailinabox/conf/nginx.conf
# sed -i "s/listen 443/listen 4413/" /mailinabox/conf/nginx.conf
# sed -i "s/:80/:810/" /mailinabox/conf/nginx.conf
# sed -i "s/:443/:4413/" /mailinabox/conf/nginx.conf

# adds --nodetach so that spampd runs in the foreground and can fork processes
sed -i "s/--setsid/--setsid --nodetach/" /lib/systemd/system/spampd.service

# insert bunch of services to start to the end of /mailinabox/setup/munin.sh

## with nsd and named
sed -i "s/restart_service munin-node/sed -i \"s\/\^PIDFile=\/\#PIDFile\/\" \/usr\/lib\/systemd\/system\/spampd.service;sed -i \"s\/\^PIDFile=\/\#PIDFile\/\" \/usr\/lib\/systemd\/system\/opendkim.service;sed -i \"s\/-xf\/-xfv\/\" \/lib\/systemd\/system\/fail2ban.service;sed -i \"s\/\^PIDFile=\/\#PIDFile\/\" \/usr\/lib\/systemd\/system\/opendmarc.service; systemctl daemon-reload; systemctl stop named; systemctl enable --now fail2ban postfix postgrey dovecot spampd nginx php8.1-fpm mailinabox munin opendkim opendmarc spamassassin nsd; systemctl start nsd; systemctl enable --now named; systemctl start named spampd; return/" /mailinabox/setup/munin.sh

## without nsd and named
# sed -i "s/restart_service munin-node/sed -i \"s\/\^PIDFile=\/\#PIDFile\/\" \/usr\/lib\/systemd\/system\/spampd.service;sed -i \"s\/\^PIDFile=\/\#PIDFile\/\" \/usr\/lib\/systemd\/system\/opendkim.service;sed -i \"s\/-xf\/-xfv\/\" \/lib\/systemd\/system\/fail2ban.service;sed -i \"s\/\^PIDFile=\/\#PIDFile\/\" \/usr\/lib\/systemd\/system\/opendmarc.service; systemctl daemon-reload; systemctl stop named; systemctl enable --now fail2ban postfix postgrey dovecot spampd nginx php8.1-fpm mailinabox munin opendkim opendmarc spamassassin; systemctl start spampd; return/" /mailinabox/setup/munin.sh

sudo setup/start.sh

## START: After install
/home/user-data/after-install.sh
## END After install

# Install missing Python dependencies for the management daemon
pip3 install boto3 qrcode pyotp 2>/dev/null || true

# Write the hostname and env for the management daemon
echo "$1" > /home/user-data/mailinabox.hostname 2>/dev/null || true

# Create management daemon service
cat > /usr/local/bin/mailinabox-daemon << "SVC"
#!/bin/bash
cd /mailinabox/management
export STORAGE_ROOT=/home/user-data
export PRIMARY_HOSTNAME=$(cat /home/user-data/mailinabox.hostname 2>/dev/null || hostname -f)
export PUBLIC_IP=$(curl -s http://checkip.amazonaws.com 2>/dev/null || hostname -I | awk '{print $1}')
export PUBLIC_IPV6=
exec python3 daemon.py
SVC
chmod +x /usr/local/bin/mailinabox-daemon

cat > /etc/systemd/system/mailinabox.service << "UNIT"
[Unit]
Description=Mail-in-a-Box Management Daemon
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/mailinabox-daemon
Restart=always
User=root
[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now mailinabox 2>/dev/null || true

# Provision Let's Encrypt certificate for the mail hostname
echo "- Provisioning Let's Encrypt certificate for $1"
service nginx stop 2>/dev/null || true
certbot certonly --standalone --non-interactive --agree-tos \
  -m admin@$(echo $1 | sed 's/^mail\.//') \
  -d "$1" \
  --preferred-challenges http 2>/dev/null || true
service nginx start 2>/dev/null || true

# Ensure Roundcube is installed (MIAB webmail.sh may fail in Docker)
if [ ! -f /usr/local/lib/roundcubemail/index.php ]; then
  echo "- Installing Roundcube webmail..."
  RC_VER="1.6.10"
  wget -q -O /tmp/roundcube.tar.gz \
    "https://github.com/roundcube/roundcubemail/releases/download/$RC_VER/roundcubemail-$RC_VER-complete.tar.gz" 2>/dev/null || \
  curl -sL -o /tmp/roundcube.tar.gz \
    "https://github.com/roundcube/roundcubemail/releases/download/$RC_VER/roundcubemail-$RC_VER-complete.tar.gz" 2>/dev/null
  if [ -f /tmp/roundcube.tar.gz ]; then
    tar -xzf /tmp/roundcube.tar.gz -C /usr/local/lib/ 2>/dev/null
    mv /usr/local/lib/roundcubemail-$RC_VER /usr/local/lib/roundcubemail 2>/dev/null || true
    rm -f /tmp/roundcube.tar.gz
  fi
fi

# Configure Dovecot to use SQL authentication (MIAB setup may skip this in Docker)
echo "- Configuring Dovecot SQL authentication"
sed -i "s/^!include auth-system.conf.ext/##!include auth-system.conf.ext/" /etc/dovecot/conf.d/10-auth.conf 2>/dev/null || true
sed -i "s/^##!include auth-sql.conf.ext/!include auth-sql.conf.ext/" /etc/dovecot/conf.d/10-auth.conf 2>/dev/null || true
grep -q "auth-sql.conf.ext" /etc/dovecot/conf.d/10-auth.conf || echo "!include auth-sql.conf.ext" >> /etc/dovecot/conf.d/10-auth.conf

cat > /etc/dovecot/dovecot-sql.conf.ext << "SQLEND"
driver = sqlite
connect = /home/user-data/mail/users.sqlite
default_pass_scheme = SHA512-CRYPT
password_query = SELECT email AS user, password FROM users WHERE email = '%u'
user_query = SELECT email AS user, 'mail' AS uid, 'mail' AS gid, '/home/user-data/mail/mailboxes/%d/%n' AS home FROM users WHERE email = '%u'
iterate_query = SELECT email AS user FROM users
SQLEND
chmod 0600 /etc/dovecot/dovecot-sql.conf.ext

# Fix Dovecot UID settings: mail system user has UID 8 but default first_valid_uid is 500
sed -i "s/^first_valid_uid = .*/first_valid_uid = 0/" /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || \
  echo "first_valid_uid = 0" >> /etc/dovecot/conf.d/10-mail.conf
printf "mail_uid = 8\nmail_gid = 8\n" >> /etc/dovecot/conf.d/99-local.conf 2>/dev/null || true

# Prevent Dovecot from pre-authenticating local connections (PREAUTH)
echo "login_trusted_networks =" >> /etc/dovecot/conf.d/99-local.conf 2>/dev/null || true

# Enable Sieve plugin for LMTP delivery (required for mail forwarding)
sed -i "s/  #mail_plugins = .*/  mail_plugins = \$mail_plugins sieve/" /etc/dovecot/conf.d/20-lmtp.conf 2>/dev/null || true

doveadm reload 2>/dev/null || true

# Configure Postfix virtual mailbox delivery
cat > /etc/postfix/virtual-mailbox-domains.cf << EOF
dbpath=/home/user-data/mail/users.sqlite
query = SELECT 1 FROM users WHERE email LIKE "\%\@%s" UNION SELECT 1 FROM aliases WHERE source LIKE "\%\@%s" UNION SELECT 1 FROM auto_aliases WHERE source LIKE "\%\@%s"
EOF
cat > /etc/postfix/virtual-mailbox-maps.cf << EOF
dbpath=/home/user-data/mail/users.sqlite
query = SELECT 1 FROM users WHERE email="%s"
EOF
cat > /etc/postfix/virtual-alias-maps.cf << EOF
dbpath=/home/user-data/mail/users.sqlite
query = SELECT destination FROM aliases WHERE source="%s"
EOF
postconf -e virtual_mailbox_domains=sqlite:/etc/postfix/virtual-mailbox-domains.cf
postconf -e virtual_mailbox_maps=sqlite:/etc/postfix/virtual-mailbox-maps.cf
postconf -e virtual_alias_maps=sqlite:/etc/postfix/virtual-alias-maps.cf
postconf -e local_recipient_maps=\$virtual_mailbox_maps
postconf -e virtual_transport=lmtp:[127.0.0.1]:10025
postconf -e smtputf8_enable=no
postfix reload 2>/dev/null || true

# Write nginx config with admin panel + Roundcube
cat > /etc/nginx/sites-enabled/default << "NGINX"
upstream php-fpm { server unix:/var/run/php/php8.1-fpm.sock; }
server {
    listen 80 default_server; listen [::]:80 default_server; server_tokens off;
    location / { return 301 https://$host$request_uri; }
    location /.well-known/acme-challenge/ {
        alias /home/user-data/ssl/lets_encrypt/webroot/.well-known/acme-challenge/;
    }
}
server {
    listen 443 ssl http2 default_server; listen [::]:443 ssl http2 default_server;
    server_tokens off;
    ssl_certificate /home/user-data/ssl/ssl_certificate.pem;
    ssl_certificate_key /home/user-data/ssl/ssl_private_key.pem;
    root /home/user-data/www; index index.html index.htm;

    location /admin/ {
        proxy_pass http://127.0.0.1:10222/;
        proxy_set_header X-Forwarded-For $remote_addr;
    }

    location = /mail { return 302 /mail/; }

    rewrite ^/mail/$ /mail/index.php;
    location /mail/ { alias /usr/local/lib/roundcubemail/; }
    location ~ /mail/config/.* { return 403; }
    location ~ /mail/.*\.php$ {
        include fastcgi_params;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME /usr/local/lib/roundcubemail/index.php;
        fastcgi_pass php-fpm;
    }
}
NGINX

# Write Roundcube config
if [ -f /usr/local/lib/roundcubemail/index.php ]; then
  MAIL_HOST="$1"
  cat > /usr/local/lib/roundcubemail/config/config.inc.php << RCCONF
<?php
\$config = [];
\$config["db_dsnw"] = "sqlite:////home/user-data/mail/roundcube/roundcube.sqlite?mode=0640";
\$config["default_host"] = "ssl://${MAIL_HOST}";
\$config["default_port"] = 993;
\$config["auth_type"] = "PLAIN";
\$config["session_domain"] = "";
\$config["session_path"] = "/";
\$config["imap_conn_options"] = ["ssl" => ["verify_peer" => false, "verify_peer_name" => false, "allow_self_signed" => true]];
\$config["smtp_server"] = "tls://${MAIL_HOST}";
\$config["smtp_port"] = 587;
\$config["smtp_user"] = "%u";
\$config["smtp_pass"] = "%p";
\$config["support_url"] = "";
\$config["product_name"] = "Mail-in-a-Box Webmail";
\$config["plugins"] = ["archive", "markasjunk", "managesieve"];
\$config["managesieve_host"] = "127.0.0.1";
\$config["managesieve_port"] = 4190;
\$config["managesieve_usetls"] = false;
\$config["enable_spellcheck"] = true;
\$config["spellcheck_engine"] = "pspell";
\$config["des_key"] = "rcmail-24byteDESkey*Str";
RCCONF
  chown -R www-data:www-data /usr/local/lib/roundcubemail 2>/dev/null || true
fi

# Reload nginx with the new config
nginx -t && nginx -s reload 2>/dev/null || true

service --status-all
/status-check.sh
