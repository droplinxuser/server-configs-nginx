#!/usr/bin/env bash
#===============================================================================
# nginx_conf.sh - Angie/Nginx config deployer
#
# Downloads (or consumes CONFIG_SOURCE_DIR) the droplinxuser/server-configs-nginx
# tree, syncs it into /etc/angie, creates the shared certificate and cache/log
# directories, tests the configuration and reloads Angie.
#
# The sync is intentionally owner-safe: source ownership is never copied into
# /etc, so a non-root account that owns a Git checkout cannot modify live web
# server configuration.
#===============================================================================
set -Eeuo pipefail

REPO_BASE=${CONFIG_REPO_URL:-https://github.com/droplinxuser/server-configs-nginx}
REPO_REF=${CONFIG_REPO_REF:-main}
REPO_URL="${REPO_BASE}/archive/${REPO_REF}.zip"
TARGET_DIR="/etc/angie"
LOG_DIR="/var/www/logs/angie"
CACHE_DIRS=(/home/nginx_cache /home/nginx_cache_chev /home/xf_proxy_cache
            /home/proxy_cache /home/proxy_cdn)

echo "==> Deploying Angie configs from server-configs-nginx..."

if [[ -n ${CONFIG_SOURCE_DIR:-} && -d ${CONFIG_SOURCE_DIR} ]]; then
    WORK_DIR=$CONFIG_SOURCE_DIR
    echo "    Using local config source: $WORK_DIR"
else
    WORK_DIR="$HOME/server-configs-nginx-main"
    ZIP_FILE="$HOME/main.zip"

    rm -rf "$WORK_DIR" "$ZIP_FILE" "${ZIP_FILE%.*}"*
    echo "    Downloading $REPO_URL ..."
    wget -q "$REPO_URL" -O "$ZIP_FILE"
    echo "    Extracting..."
    unzip -q "$ZIP_FILE" -d "$HOME"
fi

echo "    Syncing to $TARGET_DIR ..."
# --no-owner/--no-group + --chmod prevents a checkout owned by uid 1000 from
# leaving writable files in /etc/angie. Never copy the sample private key.
rsync -a --no-owner --no-group --chmod=D755,F644 \
    --exclude='*.md' --exclude='*.txt' --exclude='.git*' \
    --exclude='.github/' --exclude='test/' --exclude='.editorconfig' \
    --exclude='h5bp/tls/private.key' --exclude='h5bp/tls/certificate.pem' \
    "$WORK_DIR"/ "$TARGET_DIR"/
mkdir -p "$TARGET_DIR/snippets" "$TARGET_DIR/custom.d"
# Remove macOS AppleDouble files that can appear when a local checkout is
# used via CONFIG_SOURCE_DIR.
find "$TARGET_DIR" -name '._*' -delete 2>/dev/null || true

# Remove sample keys and old setup.sh-managed overrides that duplicated the
# cache zones, log_format and limiter variables now provided by this tree.
rm -rf "$TARGET_DIR/test"
# Remove legacy upstream demo/error pages and sample key files that older
# deployments may still have.
rm -f "$TARGET_DIR"/v3.html "$TARGET_DIR"/ua.html "$TARGET_DIR"/503.html \
      "$TARGET_DIR"/ssl/default/certificate.pem "$TARGET_DIR"/ssl/default/private.key
# Superseded / unsupported sample templates.
rm -f "$TARGET_DIR"/conf.d/templates/sample_basic_php.conf \
      "$TARGET_DIR"/conf.d/templates/sample_psi.conf \
      "$TARGET_DIR"/conf.d/templates/sample_pingvin_proxy.conf \
      "$TARGET_DIR"/conf.d/templates/sample_proxy_pass.conf
# Older deployments copied PHP-FPM configs into /etc/angie/scripts. PHP-FPM is
# not Angie config; its templates now live in ubuntu-setup-script/configs/php.
rm -f "$TARGET_DIR"/scripts/www_*.conf \
      "$TARGET_DIR/scripts/custom_dan.ini" \
      "$TARGET_DIR/scripts/php-fpm-limits.conf"
rm -f "$TARGET_DIR/scripts/auto_tune.sh" \
      "$TARGET_DIR/http.d/98_setup_cache.conf" \
      "$TARGET_DIR/http.d/99_setup_overrides.conf" \
      "$TARGET_DIR/http.d/limit_req_whitelist.conf" \
      "$TARGET_DIR/http.d/fastcgi_cache_conf" \
      "$TARGET_DIR/http.d/fastcgi_cache_chev_conf" \
      "$TARGET_DIR/http.d/xf_proxy_cache_conf" \
      "$TARGET_DIR/http.d/xf_websocket_conf" \
      "$TARGET_DIR/http.d/limit_req_conf" \
      "$TARGET_DIR/http.d/proxy_cache_conf" \
      "$TARGET_DIR/http.d/referer_map_conf" \
      "$TARGET_DIR/h5bp/limit_req/_high_conf" \
      "$TARGET_DIR/h5bp/limit_req/_medium_conf" \
      "$TARGET_DIR/h5bp/tls/private.key" \
      "$TARGET_DIR/h5bp/tls/certificate.pem"

# Normalise ownership/modes for everything except operator certificates and
# stream configs. scripts/*.sh stay executable for the Cloudflare cron job.
find "$TARGET_DIR" -path "$TARGET_DIR/ssl" -prune -o \
     -path "$TARGET_DIR/stream.d" -prune -o \
     -exec chown root:root {} + 2>/dev/null || true
find "$TARGET_DIR" -path "$TARGET_DIR/ssl" -prune -o \
     -path "$TARGET_DIR/stream.d" -prune -o \
     -type d -exec chmod 755 {} + 2>/dev/null || true
find "$TARGET_DIR" -path "$TARGET_DIR/ssl" -prune -o \
     -path "$TARGET_DIR/stream.d" -prune -o \
     -type f -exec chmod 644 {} + 2>/dev/null || true
chmod 755 "$TARGET_DIR"/scripts/*.sh 2>/dev/null || true

# The catch-all 443 server needs a unique local certificate. The repository
# used to ship a shared sample key; generate one per host instead.
if [[ ! -s "$TARGET_DIR/ssl/default/fullchain.pem" \
      || ! -s "$TARGET_DIR/ssl/default/privkey.pem" ]]; then
    echo "    Generating the default self-signed certificate..."
    install -d -m 700 "$TARGET_DIR/ssl/default"
    openssl req -x509 -nodes -newkey rsa:2048 -days 397 \
        -subj "/CN=$(hostname -f 2>/dev/null || hostname)" \
        -addext "subjectAltName=DNS:$(hostname -f 2>/dev/null || hostname)" \
        -keyout "$TARGET_DIR/ssl/default/privkey.pem" \
        -out "$TARGET_DIR/ssl/default/fullchain.pem" >/dev/null 2>&1
    chmod 600 "$TARGET_DIR/ssl/default/privkey.pem"
    chmod 644 "$TARGET_DIR/ssl/default/fullchain.pem"
fi

#-------------------------------------------------------------------------------
# Central log and cache directories. All service logs live under
# /var/www/logs so they can be collected as one tree.
#-------------------------------------------------------------------------------
echo "    Creating log and cache directories..."
install -d -m 750 -o www-data -g www-data "$LOG_DIR"
[[ -e "$LOG_DIR/error.log" ]] || : > "$LOG_DIR/error.log"
chown www-data:www-data "$LOG_DIR/error.log" 2>/dev/null || true
chmod 640 "$LOG_DIR/error.log"

for cache_dir in "${CACHE_DIRS[@]}"; do
    mkdir -p "$cache_dir"
    chown www-data:www-data "$cache_dir" 2>/dev/null || true
    chmod 750 "$cache_dir"
done

#-------------------------------------------------------------------------------
# Test the config and reload Angie if valid
#-------------------------------------------------------------------------------
# Hardware-aware tuning is owned by ubuntu-setup-script/setup.sh so the same
# code runs during install and `setup.sh --optimize`.  This script only syncs
# the repository tree; setup.sh applies the tuning before the final reload.
echo "    Testing Angie configuration..."
if /usr/sbin/angie -t; then
    echo "    Configuration OK - reloading Angie..."
    /usr/bin/systemctl daemon-reload || true
    /usr/bin/systemctl reload angie.service
    # Angie's master opens log files as root. Normalise pre-existing logs for
    # the UMask=0027 drop-in; new files are already 0640.
    find "$LOG_DIR" -type f -name '*.log' -exec chmod 640 {} + 2>/dev/null || true
    echo "    Done."
else
    echo "    ERROR: Angie configuration test failed. Reload aborted." >&2
    exit 1
fi
