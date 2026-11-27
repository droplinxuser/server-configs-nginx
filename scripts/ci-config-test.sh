#!/usr/bin/env bash
# Configuration test for this tree, as CI runs it.
#
# Installs the tree the way ubuntu-setup-script 1.22 does (nginx.conf and the
# tree's own fastcgi.conf/fastcgi_params into /etc/nginx, the Brotli stanza
# from http.d/brotli_conf as plain directives, a self-signed default
# certificate, the tmpfiles directories), renders every vhost template under
# conf.d/templates with its own test hostname and certificate, and runs
# `nginx -t` on the base tree and again with all templates.  Then it starts
# the binary on 127.0.0.1 with a throwaway configuration and checks that a 404
# names nginx in neither the headers nor the body (the build's branding patch).
#
# The binary is the one ubuntu-setup-script ships, built by
# scripts/ci-build-nginx.sh (tools/nginx-build.sh with NGINX_BUILD_CI=1: the
# same configure module set, no LTO/BOLT/-march=native).  nginx.org's package
# would test the wrong binary: it has no Brotli and carries the modules the
# lean build leaves out (ssi, limit_conn, autoindex, scgi, uwsgi, ...), so a
# template using one of those would pass here and fail on every host.
#
# Run as root on a throwaway machine (a CI runner).
#
#   NGINX_BIN       the nginx binary to test (required).
#   PREFIX          where the tree goes (default /etc/nginx).  Another prefix
#                   leaves a live /etc/nginx alone: every /etc/nginx path in
#                   the copy is rewritten to it.  PREFIX is deleted and
#                   recreated, so after canonicalisation (symlinks and ..
#                   resolved) it must be exactly /etc/nginx or a directory
#                   below /tmp or below $RUNNER_TEMP, and may not contain or
#                   sit inside this checkout.  An existing non-empty PREFIX
#                   is only replaced in CI (CI=true) or with FORCE=1.
#   SKIP_TEMPLATES=1  test only the base tree.
#   REQUIRE_BROTLI=0  allow a binary without the static ngx_brotli module
#                     (brotli.conf is then left out); CI keeps the default 1.
#                     A dynamic ngx_brotli (--add-dynamic-module) is always
#                     refused: the tree has no load_module line.
#   SKIP_BRANDING=1   skip the 404 branding check.
set -Eeuo pipefail

TREE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PREFIX=${PREFIX:-/etc/nginx}
NGINX_BIN=${NGINX_BIN:-}
WORK=$(mktemp -d)
BRAND_PID=""
cleanup() {
  if [[ -n $BRAND_PID ]]; then kill -QUIT "$BRAND_PID" 2>/dev/null || true; fi
  rm -rf "${WORK:?}"
}
trap cleanup EXIT

say() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

selfsigned() { # dir cn
  mkdir -p "$1"
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
    -days 2 -subj "/CN=$2" -keyout "$1/privkey.pem" -out "$1/fullchain.pem" \
    >/dev/null 2>&1
}

[[ $EUID -eq 0 ]] || die "run as root (the tree goes to ${PREFIX} and nginx -t opens /var/www/logs/nginx)"
[[ -n $NGINX_BIN && -x $NGINX_BIN ]] || die "NGINX_BIN must name an executable nginx (scripts/ci-build-nginx.sh prints it)"
build_args=$("$NGINX_BIN" -V 2>&1)
printf '%s\n' "$build_args" | sed 's/^/    /'

# PREFIX is removed with rm -rf below, so it is checked against an
# allow-list after canonicalisation, not a deny-list of system paths: a
# deny-list misses /etc/nginx/.., /opt, a symlink to /, or a typo that lands
# on a live directory.
[[ $PREFIX =~ ^/[A-Za-z0-9._/-]*$ ]] \
  || die "PREFIX=${PREFIX} must be an absolute path of letters, digits, '.', '_', '-' and '/' (it is also a sed replacement)"
PREFIX=$(realpath -m -- "$PREFIX") || die "cannot canonicalise PREFIX=${PREFIX}"
under() { # PATH DIR: PATH is strictly below DIR
  [[ -n $2 && $1 == "${2%/}"/?* ]]
}
prefix_ok=0
if [[ $PREFIX == /etc/nginx ]] || under "$PREFIX" /tmp; then
  prefix_ok=1
elif [[ -n ${RUNNER_TEMP:-} ]]; then
  runner_temp=$(realpath -m -- "$RUNNER_TEMP") || runner_temp=""
  if [[ $runner_temp == /?* ]] && under "$PREFIX" "$runner_temp"; then prefix_ok=1; fi
fi
[[ $prefix_ok == 1 ]] \
  || die "PREFIX=${PREFIX} is not allowed: use /etc/nginx, a directory below /tmp, or one below \$RUNNER_TEMP"
# Never delete the checkout under test or the staging copy.
for keep in "$TREE" "$WORK"; do
  keep=$(realpath -m -- "$keep")
  if [[ $PREFIX == "$keep" ]] || under "$PREFIX" "$keep" || under "$keep" "$PREFIX"; then
    die "PREFIX=${PREFIX} overlaps ${keep}"
  fi
done
if [[ -d $PREFIX && -n $(ls -A "$PREFIX" 2>/dev/null) ]] \
  && [[ ${CI:-} != true && ${FORCE:-0} != 1 ]]; then
  die "${PREFIX} is not empty; refusing to replace a live tree (use PREFIX=/tmp/scn-test, or FORCE=1)"
fi

say "installing the tree into ${PREFIX}"
# Everything comes from this tree, the FastCGI parameter files included: a
# source build installs no package files, and the tree's copies pass
# SERVER_SOFTWARE from $fastcgi_server_software (http.d/server_software.conf:
# "nginx", or nginx/<version> on admin.php only; scripts/ci-guards.sh).
stage=$WORK/stage
mkdir -p "$stage"
cp -a "$TREE"/nginx.conf "$TREE"/mime.types "$TREE"/fastcgi.conf "$TREE"/fastcgi_params \
  "$TREE"/conf.d "$TREE"/h5bp "$TREE"/http.d "$TREE"/snippets "$stage"/
rm -rf "${PREFIX:?}"
mkdir -p "$PREFIX"
cp -a "$stage"/. "$PREFIX"/
mkdir -p "$PREFIX"/custom.d
if [[ $PREFIX != /etc/nginx ]]; then
  grep -rlF /etc/nginx "$PREFIX" | while IFS= read -r f; do
    sed -i "s#/etc/nginx#${PREFIX}#g" "$f"
  done
fi

# Brotli is a static module (--add-module): plain directives in
# http.d/brotli.conf, the way ubuntu-setup-script renders it; never a
# load_module line.  Match the configure argument itself, not any mention of
# ngx_brotli: a dynamic build (--add-dynamic-module) names it too, and with
# no load_module in the tree its directives would fail on every host.  Since
# ubuntu-setup-script 1.22.1 the argument is --add-module=.../ngx_brotli/filter
# (the filter only; the tree has no brotli_static), which this still matches.
if grep -qE -- '--add-dynamic-module=[^ ]*ngx_brotli' <<<"$build_args"; then
  die "the binary has ngx_brotli as a dynamic module (--add-dynamic-module); the shipped build compiles it in statically"
fi
if grep -qE -- '--add-module=[^ ]*ngx_brotli' <<<"$build_args"; then
  cp "$PREFIX"/http.d/brotli_conf "$PREFIX"/http.d/brotli.conf
elif [[ ${REQUIRE_BROTLI:-1} == 1 ]]; then
  die "the binary has no static ngx_brotli (--add-module); the shipped build always has it"
else
  say "no ngx_brotli in this binary: http.d/brotli.conf left out (REQUIRE_BROTLI=0)"
fi

# What tmpfiles.d/setup-nginx.conf creates on a host: the compiled-in temp
# paths (--http-*-temp-path) and the log directory.
install -d -m 0700 -o www-data -g www-data /var/cache/nginx
for t in client fastcgi proxy scgi uwsgi; do
  install -d -m 0700 -o www-data -g www-data "/var/cache/nginx/${t}_temp"
done
install -d -m 0750 -o www-data -g www-data /var/www/logs/nginx
mkdir -p /home/nginx_cache /home/nginx_cache_chev /home/proxy_cache \
  /home/proxy_cdn /home/xf_proxy_cache /var/lib/php
selfsigned "$PREFIX"/ssl/default localhost

say "base tree: nginx -t"
"$NGINX_BIN" -t -c "$PREFIX"/nginx.conf

if [[ ${SKIP_TEMPLATES:-0} != 1 ]]; then
  # Each template becomes one vhost on its own hostname.  domain.com is the
  # templates' placeholder; site-N.example are reserved names (RFC 2606).
  n=0
  for t in "$TREE"/conf.d/templates/*.conf; do
    n=$((n + 1))
    host="site-${n}.example"
    name=$(basename "$t" .conf)
    sed -e "s/domain\\.com/${host}/g" -e "s/example\\.com/${host}/g" \
      -e "s#/etc/nginx#${PREFIX}#g" "$t" > "$PREFIX/conf.d/zz-ci-${name}.conf"
    selfsigned "/etc/letsencrypt/live/${host}" "$host"
    mkdir -p "/var/www/${host}/public" "/var/www/cdn.${host}/public" \
      "/var/www/cp.${host}"
  done
  say "${n} templates as vhosts: nginx -t"
  "$NGINX_BIN" -t -c "$PREFIX"/nginx.conf
fi

if [[ ${SKIP_BRANDING:-0} != 1 ]]; then
  # The build patches out the default Server header (HTTP/1, HTTP/2, HTTP/3)
  # and the "<hr><center>nginx</center>" error-page tail.  server_tokens is
  # left at its default (on) here on purpose: an unpatched binary would then
  # send "Server: nginx/<version>".  Only HTTP/1.1 is probed (no TLS here).
  say "branding: a 404 must not name nginx"
  bd=$WORK/brand
  mkdir -p "$bd"
  port=$(( 20000 + RANDOM % 20000 ))
  cat > "$bd/nginx.conf" <<EOF
worker_processes 1;
pid $bd/nginx.pid;
error_log $bd/error.log warn;
events { worker_connections 64; }
http {
  access_log off;
  client_body_temp_path $bd/client;
  proxy_temp_path $bd/proxy;
  fastcgi_temp_path $bd/fastcgi;
  server {
    listen 127.0.0.1:${port};
    location / { return 404; }
  }
}
EOF
  "$NGINX_BIN" -p "$bd" -c "$bd/nginx.conf"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -s $bd/nginx.pid ]] && break
    sleep 0.5
  done
  if [[ ! -s $bd/nginx.pid ]]; then
    cat "$bd/error.log" >&2 || true
    die "the branding test server did not start"
  fi
  BRAND_PID=$(cat "$bd/nginx.pid")
  resp=$(curl -sS -i --max-time 10 "http://127.0.0.1:${port}/ci-missing")
  printf '%s\n' "$resp" | sed 's/^/    /'
  grep -q '^HTTP/[0-9.]* 404' <<<"$resp" || die "expected a 404 from the branding test server"
  if grep -qi 'nginx' <<<"$resp"; then
    die "the 404 names nginx (Server header or error-page footer): the branding patch is missing from this build"
  fi
  kill -QUIT "$BRAND_PID" 2>/dev/null || true
  BRAND_PID=""
fi
say "OK"
