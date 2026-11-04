#!/usr/bin/env bash
#===============================================================================
# auto_tune.sh - hardware-aware tuning for the Angie/Nginx config tree
#
# Called by nginx_conf.sh after the repository has been synced into
# /etc/angie.  Every value is derived from the live host (nproc, MemTotal,
# free disk space and the backing storage type), so the same repository works
# on a 1 GB VPS and a 128 GB dedicated server without editing files.
#
# The script is idempotent: nginx_conf.sh always re-syncs the pristine tree
# first, then this script rewrites the small set of tunable directives.
#===============================================================================
set -Eeuo pipefail

TARGET_DIR=${1:-/etc/angie}
NGINX_CONF="$TARGET_DIR/angie.conf"

log() { printf '    [tune] %s\n' "$*"; }
clamp() {
    local value=$1 min=$2 max=$3
    (( value < min )) && value=$min
    (( value > max )) && value=$max
    printf '%s' "$value"
}

# ---------------------------------------------------------------------------
# Host inventory
# ---------------------------------------------------------------------------
NPROC=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
(( NPROC > 0 )) || NPROC=1
MEM_MB=$(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 1024)
(( MEM_MB > 0 )) || MEM_MB=1024

DISK_CLASS=hdd
if compgen -G '/sys/block/nvme*' >/dev/null 2>&1; then
    DISK_CLASS=nvme
elif command -v lsblk >/dev/null 2>&1 && lsblk -d -n -o ROTA 2>/dev/null | grep -q '^0'; then
    DISK_CLASS=ssd
fi

DISK_FREE_MB=$(df -Pm /var/www 2>/dev/null | awk 'NR==2{print $4}')
[[ $DISK_FREE_MB =~ ^[0-9]+$ ]] || DISK_FREE_MB=$(df -Pm / | awk 'NR==2{print $4}')
[[ $DISK_FREE_MB =~ ^[0-9]+$ ]] || DISK_FREE_MB=10240

# ---------------------------------------------------------------------------
# Angie core / event loop
# ---------------------------------------------------------------------------
# Keep enough descriptors for every worker connection plus cached file
# descriptors, but never exceed the systemd LimitNOFILE drop-in (524288).
WORKER_RLIMIT=$(clamp $(( NPROC * 8192 )) 65536 524288)
WORKER_CONNECTIONS=$(clamp $(( NPROC * 2048 )) 8192 65535)
(( WORKER_CONNECTIONS > WORKER_RLIMIT - 1024 )) && WORKER_CONNECTIONS=$(( WORKER_RLIMIT - 1024 ))
(( WORKER_CONNECTIONS < 1024 )) && WORKER_CONNECTIONS=1024
PHP_KEEPALIVE=$(clamp $(( NPROC * 2 )) 16 128)
OPEN_FILES=$(clamp $(( NPROC * 2048 )) 10000 200000)

# Small hosts should not reserve large per-request buffers for hundreds of
# workers that will never exist.
# fastcgi_busy_buffers_size must stay below (buffers - one buffer), otherwise
# Angie rejects the whole configuration.  Keep a full buffer of headroom.
if (( MEM_MB < 2048 )); then
    FASTCGI_BUFFERS='32 16k'
    FASTCGI_BUSY='256k'
    BODY_BUFFER='64k'
elif (( MEM_MB < 8192 )); then
    FASTCGI_BUFFERS='64 32k'
    FASTCGI_BUSY='1m'
    BODY_BUFFER='128k'
else
    FASTCGI_BUFFERS='128 32k'
    FASTCGI_BUSY='2m'
    BODY_BUFFER='256k'
fi

# TLS session cache: 1 MiB stores roughly 4000 sessions.  Scale from 10 MiB
# on tiny hosts to 256 MiB on large ones.
SSL_CACHE_MB=$(clamp $(( MEM_MB / 512 )) 10 256)

# ---------------------------------------------------------------------------
# Cache budget
# ---------------------------------------------------------------------------
# Never spend more than 25% of RAM or 5% of free disk on HTTP caches.
CACHE_TOTAL_MB=$(( MEM_MB * 25 / 100 ))
(( CACHE_TOTAL_MB > 65536 )) && CACHE_TOTAL_MB=65536
(( CACHE_TOTAL_MB > DISK_FREE_MB * 5 / 100 )) && CACHE_TOTAL_MB=$(( DISK_FREE_MB * 5 / 100 ))
(( CACHE_TOTAL_MB < 256 )) && CACHE_TOTAL_MB=256

FCGI_MB=$(( CACHE_TOTAL_MB * 50 / 100 ))
CHEV_MB=$(( CACHE_TOTAL_MB * 25 / 100 ))
XF_MB=$(( CACHE_TOTAL_MB * 15 / 100 ))
PROXY_MB=$(( CACHE_TOTAL_MB * 5 / 100 ))
CDN_MB=$(( CACHE_TOTAL_MB * 5 / 100 ))
(( FCGI_MB < 64 )) && FCGI_MB=64
(( CHEV_MB < 32 )) && CHEV_MB=32
(( XF_MB < 32 )) && XF_MB=32
(( PROXY_MB < 16 )) && PROXY_MB=16
(( CDN_MB < 16 )) && CDN_MB=16

FCGI_ZONE=$(clamp $(( CACHE_TOTAL_MB / 4 )) 16 512)
CHEV_ZONE=$(clamp $(( CACHE_TOTAL_MB / 8 )) 8 512)
XF_ZONE=$(clamp $(( CACHE_TOTAL_MB / 8 )) 8 256)
PROXY_ZONE=$(clamp $(( CACHE_TOTAL_MB / 16 )) 8 128)
CDN_ZONE=$(clamp $(( CACHE_TOTAL_MB / 16 )) 8 128)

size_value() {
    local mb=$1
    if (( mb >= 1024 && mb % 1024 == 0 )); then
        printf '%sG' $(( mb / 1024 ))
    else
        printf '%sM' "$mb"
    fi
}
FCGI_SIZE=$(size_value "$FCGI_MB")
CHEV_SIZE=$(size_value "$CHEV_MB")
XF_SIZE=$(size_value "$XF_MB")
PROXY_SIZE=$(size_value "$PROXY_MB")
CDN_SIZE=$(size_value "$CDN_MB")

# ---------------------------------------------------------------------------
# Rewrite helpers
# ---------------------------------------------------------------------------
replace() {
    local file=$1 pattern=$2 value=$3
    [[ -f $file ]] || return 0
    sed -i -E "s|${pattern}|${value}|" "$file"
}

[[ -f $NGINX_CONF ]] || { echo "auto_tune.sh: $NGINX_CONF not found" >&2; exit 1; }

replace "$NGINX_CONF" '^([[:space:]]*worker_rlimit_nofile[[:space:]]+)[0-9]+;' "\\1${WORKER_RLIMIT};"
replace "$NGINX_CONF" '^([[:space:]]*worker_connections[[:space:]]+)[0-9]+;' "\\1${WORKER_CONNECTIONS};"
replace "$NGINX_CONF" '^([[:space:]]*client_body_buffer_size[[:space:]]+).*;' "\\1${BODY_BUFFER};"
replace "$NGINX_CONF" '^([[:space:]]*keepalive[[:space:]]+)[0-9]+;' "\\1${PHP_KEEPALIVE};"

# TLS session cache in every server block that includes this file.
replace "$TARGET_DIR/h5bp/tls/ssl_engine.conf" \
    '^([[:space:]]*ssl_session_cache[[:space:]]+shared:SSL:)[0-9]+m;' "\\1${SSL_CACHE_MB}m;"

# File-descriptor cache.
replace "$TARGET_DIR/h5bp/web_performance/cache-file-descriptors.conf" \
    'open_file_cache max=[0-9]+' "open_file_cache max=${OPEN_FILES}"
replace "$TARGET_DIR/h5bp/web_performance/cache-file-descriptors.conf" \
    'open_log_file_cache max=[0-9]+' "open_log_file_cache max=$(( OPEN_FILES / 4 ))"

# FastCGI buffer sizes in every PHP handler.
for php_conf in "$TARGET_DIR"/h5bp/php*.conf; do
    [[ -f $php_conf ]] || continue
    replace "$php_conf" '^([[:space:]]*fastcgi_buffer_size[[:space:]]+).*;' "\\1${BODY_BUFFER};"
    replace "$php_conf" '^([[:space:]]*fastcgi_buffers[[:space:]]+).*;' "\\1${FASTCGI_BUFFERS};"
    replace "$php_conf" '^([[:space:]]*fastcgi_busy_buffers_size[[:space:]]+).*;' "\\1${FASTCGI_BUSY};"
done

# Cache paths: size and keys_zone are both derived from the host budget.
replace "$TARGET_DIR/http.d/fastcgi_cache.conf" \
    'keys_zone=fastcgicache:[0-9]+m max_size=[0-9]+[mg]' "keys_zone=fastcgicache:${FCGI_ZONE}m max_size=${FCGI_SIZE}"
replace "$TARGET_DIR/http.d/fastcgi_cache_chev.conf" \
    '^(fastcgi_cache_path /home/nginx_cache_chev levels=1:2 keys_zone=fastcgicache_chev:)[0-9]+m( max_size=[0-9]+[mg])?(.*)$' \
    "\\1${CHEV_ZONE}m max_size=${CHEV_SIZE}\\3"
replace "$TARGET_DIR/http.d/proxy_cache.conf" \
    'keys_zone=proxy_cache:[0-9]+m' "keys_zone=proxy_cache:${PROXY_ZONE}m"
replace "$TARGET_DIR/http.d/proxy_cache.conf" \
    'keys_zone=proxy_cdn:[0-9]+m' "keys_zone=proxy_cdn:${CDN_ZONE}m"
# The two proxy caches are on consecutive blocks; replace max_size occurrences
# in file order (proxy first, CDN second).
if [[ -f $TARGET_DIR/http.d/proxy_cache.conf ]]; then
    awk -v a="$PROXY_SIZE" -v b="$CDN_SIZE" '
        /proxy_cache_path \/home\/proxy_cache / { sub(/max_size=[0-9]+[mg]/, "max_size=" a) }
        /proxy_cache_path \/home\/proxy_cdn /   { sub(/max_size=[0-9]+[mg]/, "max_size=" b) }
        { print }
    ' "$TARGET_DIR/http.d/proxy_cache.conf" > "$TARGET_DIR/http.d/proxy_cache.conf.new"
    mv "$TARGET_DIR/http.d/proxy_cache.conf.new" "$TARGET_DIR/http.d/proxy_cache.conf"
fi
replace "$TARGET_DIR/http.d/xf_proxy_cache.conf" \
    'keys_zone=xfproxycache:[0-9]+m max_size=[0-9]+[mg]' "keys_zone=xfproxycache:${XF_ZONE}m max_size=${XF_SIZE}"

# Request-limiting zones only need to be large on busy hosts.
LIMIT_POST=$(clamp $(( MEM_MB / 4096 )) 8 32)
LIMIT_GET=$(clamp $(( MEM_MB / 2048 )) 16 64)
replace "$TARGET_DIR/http.d/limit_req.conf" \
    'zone=limit_req_post_head:[0-9]+m' "zone=limit_req_post_head:${LIMIT_POST}m"
replace "$TARGET_DIR/http.d/limit_req.conf" \
    'zone=limit_req_get_perip:[0-9]+m' "zone=limit_req_get_perip:${LIMIT_GET}m"

# ---------------------------------------------------------------------------
# Verify the result
# ---------------------------------------------------------------------------
if ! /usr/sbin/angie -t >/tmp/angie-auto-tune-test.log 2>&1; then
    cat /tmp/angie-auto-tune-test.log >&2
    rm -f /tmp/angie-auto-tune-test.log
    echo "auto_tune.sh: generated configuration failed 'angie -t'" >&2
    exit 1
fi
rm -f /tmp/angie-auto-tune-test.log

log "hardware: ${NPROC} CPU, $(( MEM_MB / 1024 )) GiB RAM, ${DISK_CLASS} storage, $(( DISK_FREE_MB / 1024 )) GiB free"
log "angie: workers=auto connections=${WORKER_CONNECTIONS} rlimit=${WORKER_RLIMIT} php_keepalive=${PHP_KEEPALIVE}"
log "cache: total=${CACHE_TOTAL_MB}M fastcgi=${FCGI_SIZE} chevereto=${CHEV_SIZE} xf_proxy=${XF_SIZE} proxy=${PROXY_SIZE} cdn=${CDN_SIZE}"
