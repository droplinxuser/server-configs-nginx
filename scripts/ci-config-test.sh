#!/usr/bin/env bash
# Configuration test for this tree, as CI runs it.
#
# Installs the tree the way ubuntu-setup-script does (Brotli stanza from
# http.d/brotli_conf, a self-signed default certificate), renders every
# vhost template under conf.d/templates with its own test hostname and
# certificate, and runs `angie -t`.  Run as root on a throwaway machine
# (a CI runner) with Angie and angie-module-brotli installed.
#
#   PREFIX   where the tree goes (default /etc/angie).  Another prefix
#            leaves a live /etc/angie alone: every /etc/angie path in the
#            copy is rewritten to it.
#   SKIP_TEMPLATES=1  test only the base tree.
set -Eeuo pipefail

TREE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PREFIX=${PREFIX:-/etc/angie}
ANGIE=${ANGIE:-angie}
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT

say() { printf '==> %s\n' "$*"; }

selfsigned() { # dir cn
  mkdir -p "$1"
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
    -days 2 -subj "/CN=$2" -keyout "$1/privkey.pem" -out "$1/fullchain.pem" \
    >/dev/null 2>&1
}

say "installing the tree into ${PREFIX}"
# The package's parameter files (fastcgi.conf, fastcgi_params, ...) stay, as
# on a real install; the tree replaces everything else.
stage=$WORK/stage
mkdir -p "$stage"
find /etc/angie -maxdepth 1 -type f \( -name '*params' -o -name 'fastcgi.conf' \) \
  -exec cp -a {} "$stage"/ \;
cp -a "$TREE"/angie.conf "$TREE"/mime.types "$TREE"/conf.d "$TREE"/h5bp \
  "$TREE"/http.d "$TREE"/snippets "$stage"/
[[ -f $stage/fastcgi.conf ]] || { echo "no fastcgi.conf from the Angie package" >&2; exit 1; }
if [[ $PREFIX == /etc/angie ]]; then
  find /etc/angie -mindepth 1 -maxdepth 1 ! -name modules ! -name modules-enabled \
    -exec rm -rf {} +
else
  rm -rf "${PREFIX:?}"
fi
mkdir -p "$PREFIX"
cp -a "$stage"/. "$PREFIX"/
mkdir -p "$PREFIX"/custom.d "$PREFIX"/modules-enabled
if [[ $PREFIX != /etc/angie ]]; then
  grep -rlF /etc/angie "$PREFIX" | while IFS= read -r f; do
    sed -i "s#/etc/angie#${PREFIX}#g" "$f"
  done
fi

# Dynamic Brotli, the way setup.sh writes it (modules-enabled/50-brotli.conf).
mod_dir=$(dirname "$(find /usr/lib/angie/modules /usr/lib64/angie/modules \
  -name 'ngx_http_brotli_filter_module.so' 2>/dev/null | head -n 1)")
if [[ -f $PREFIX/http.d/brotli_conf && -n $mod_dir && $mod_dir != . ]]; then
  {
    printf 'load_module %s/ngx_http_brotli_filter_module.so;\n' "$mod_dir"
    printf 'load_module %s/ngx_http_brotli_static_module.so;\n' "$mod_dir"
  } > "$PREFIX"/modules-enabled/50-brotli.conf
  cp "$PREFIX"/http.d/brotli_conf "$PREFIX"/http.d/brotli.conf
else
  echo "angie-module-brotli is missing" >&2
  exit 1
fi

mkdir -p /var/www/logs/angie /home/nginx_cache /home/nginx_cache_chev \
  /home/proxy_cache /home/proxy_cdn /home/xf_proxy_cache /var/lib/php
selfsigned "$PREFIX"/ssl/default localhost

say "base tree: ${ANGIE} -t"
"$ANGIE" -t -c "$PREFIX"/angie.conf

if [[ ${SKIP_TEMPLATES:-0} == 1 ]]; then exit 0; fi

# Each template becomes one vhost on its own hostname.  domain.com is the
# templates' placeholder; site-N.example are reserved names (RFC 2606).
n=0
for t in "$TREE"/conf.d/templates/*.conf; do
  n=$((n + 1))
  host="site-${n}.example"
  name=$(basename "$t" .conf)
  sed -e "s/domain\\.com/${host}/g" -e "s/example\\.com/${host}/g" \
    -e "s#/etc/angie#${PREFIX}#g" "$t" > "$PREFIX/conf.d/zz-ci-${name}.conf"
  selfsigned "/etc/letsencrypt/live/${host}" "$host"
  mkdir -p "/var/www/${host}/public" "/var/www/cdn.${host}/public" \
    "/var/www/cp.${host}"
done
say "${n} templates as vhosts: ${ANGIE} -t"
"$ANGIE" -t -c "$PREFIX"/angie.conf
say "OK"
