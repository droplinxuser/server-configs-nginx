#!/bin/bash
#===============================================================================
# Angie Web Server — Idempotent Install & Configure Script
# Safe to run on fresh servers AND servers with Angie already installed.
# Target: Ubuntu 26.04
#===============================================================================
set -e

echo "==> Installing prerequisites..."
apt install -y --no-install-recommends ca-certificates curl wget unzip rsync

#-------------------------------------------------------------------------------
# Angie signing key (skip if already present)
#-------------------------------------------------------------------------------
if [ ! -s /etc/apt/trusted.gpg.d/angie-signing.gpg ]; then
    echo "==> Adding Angie signing key..."
    curl -fsSL https://angie.software/keys/angie-signing.gpg \
        -o /etc/apt/trusted.gpg.d/angie-signing.gpg
else
    echo "==> Angie signing key already present, skipping."
fi

#-------------------------------------------------------------------------------
# Angie APT repo (skip if already present)
#-------------------------------------------------------------------------------
if [ ! -f /etc/apt/sources.list.d/angie.list ]; then
    echo "==> Adding Angie APT repository..."
    . /etc/os-release
    echo "deb https://download.angie.software/angie/${ID}/${VERSION_ID} ${VERSION_CODENAME} main" \
        | tee /etc/apt/sources.list.d/angie.list > /dev/null
else
    echo "==> Angie APT repository already present, skipping."
fi

#-------------------------------------------------------------------------------
# Install / upgrade Angie
#-------------------------------------------------------------------------------
echo "==> Updating package lists..."
apt update -y

echo "==> Installing Angie..."
apt install -y --no-install-recommends angie

#-------------------------------------------------------------------------------
# Enable and start the service
#-------------------------------------------------------------------------------
systemctl daemon-reload
systemctl enable --now angie

echo "==> Angie service status:"
systemctl status angie --no-pager -l || true

#-------------------------------------------------------------------------------
# Fetch and run the nginx_conf.sh config deployment script
# (Idempotent — safe to re-run)
#-------------------------------------------------------------------------------
echo "==> Fetching config deployment script..."
wget -qO /root/nginx_conf.sh https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/nginx_conf.sh
chmod +x /root/nginx_conf.sh
/root/nginx_conf.sh

#-------------------------------------------------------------------------------
# Apply systemd limits and defaults
#-------------------------------------------------------------------------------
echo "==> Applying systemd limits..."
mkdir -p /etc/systemd/system/angie.service.d
wget -qO /etc/systemd/system/angie.service.d/limits.conf \
    https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/limit_nofile.conf

echo "==> Applying Angie defaults..."
wget -qO /etc/default/angie \
    https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/etc_default_nginx

#-------------------------------------------------------------------------------
# Reload everything
#-------------------------------------------------------------------------------
systemctl daemon-reload
systemctl restart angie

echo ""
echo "=============================================="
echo "  Angie is now installed and running!"
echo "=============================================="
