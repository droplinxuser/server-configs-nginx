#!/bin/bash
#===============================================================================
# nginx_conf.sh — Angie/Nginx Config Deployer
# Downloads the latest configs from the droplinxuser/server-configs-nginx repo,
# rsyncs them into /etc/angie/, tests the config, and gracefully reloads.
# Safe to re-run — fully idempotent.
#===============================================================================
set -e

REPO_URL="https://github.com/droplinxuser/server-configs-nginx/archive/refs/heads/main.zip"
WORK_DIR="$HOME/server-configs-nginx-main"
ZIP_FILE="$HOME/main.zip"
TARGET_DIR="/etc/angie"

echo "==> Deploying Angie configs from server-configs-nginx..."

#-------------------------------------------------------------------------------
# Clean up any previous extraction
#-------------------------------------------------------------------------------
rm -rf "$WORK_DIR" "$ZIP_FILE" ${ZIP_FILE%.*}*

#-------------------------------------------------------------------------------
# Download and extract the latest configs
#-------------------------------------------------------------------------------
echo "    Downloading $REPO_URL ..."
wget -q "$REPO_URL" -O "$ZIP_FILE"

echo "    Extracting..."
unzip -q "$ZIP_FILE" -d "$HOME"

#-------------------------------------------------------------------------------
# Remove non-config files (READMEs, git metadata, etc.)
#-------------------------------------------------------------------------------
rm -rf "$WORK_DIR"/{*.md,*.txt,.git*}

#-------------------------------------------------------------------------------
# Sync configs into /etc/angie/
# rsync -a (archive) preserves permissions and only adds/updates files.
# It does NOT delete existing files in /etc/angie/ that aren't in the source.
#-------------------------------------------------------------------------------
echo "    Syncing to $TARGET_DIR ..."
rsync -a "$WORK_DIR"/ "$TARGET_DIR"/

#-------------------------------------------------------------------------------
# Test the config and reload Angie if valid
#-------------------------------------------------------------------------------
echo "    Testing Angie configuration..."
if /usr/sbin/angie -t; then
    echo "    Configuration OK — reloading Angie..."
    /usr/bin/systemctl reload angie.service
    echo "    Done."
else
    echo "    ERROR: Angie configuration test failed. Reload aborted." >&2
    exit 1
fi
