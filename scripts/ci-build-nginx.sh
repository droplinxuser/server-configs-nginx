#!/usr/bin/env bash
# Build the nginx binary CI tests this tree with: ubuntu-setup-script's own
# tools/nginx-build.sh in its CI mode (NGINX_BUILD_CI=1), at the
# ubuntu-setup-script ref pinned in scripts/uss-ref.
#
# CI mode keeps the configure module set of the shipped build (the static
# ngx_brotli filter module only, --add-module=.../ngx_brotli/filter, http_v3,
# realip, threads, auth_basic, limit_req, the same left-out modules; since
# ubuntu-setup-script 1.22.1 neither gzip_static nor ngx_brotli's static
# module is compiled in) and the branding patch, and drops what only
# matters on a host or costs CI minutes: no LTO, no BOLT, no -march=native,
# no unit, no activation.  Sharing the tool means the CI binary and the
# fleet's binary cannot drift apart in which directives they accept.
#
# The binary's path is whatever the tool says it is: `build-only` prints the
# verified binary's path as the last line of stdout (its build output goes
# to stderr).  Guessing a layout here, or searching the build root for a
# file named nginx, could test a stale or unverified binary after the tool
# changes where it stages.
#
# Usage (root, on a throwaway runner):
#   ci-build-nginx.sh USS_DIR OUT_DIR
#     USS_DIR  checkout of ubuntu-setup-script at the pinned ref
#     OUT_DIR  build root (NGINX_BUILD_ROOT); the binary's path is printed
#              on the last line and written to OUT_DIR/nginx-bin.path
#   NGINX_BUILD_CACHE  source/download cache (default OUT_DIR/cache); CI
#                      points it at the directory actions/cache restores.
set -Eeuo pipefail

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ $# -eq 2 ]] || die "usage: $0 USS_DIR OUT_DIR"
USS=$(cd "$1" && pwd)
OUT=$2
TOOL=$USS/tools/nginx-build.sh
[[ -f $TOOL ]] || die "${TOOL} not found: is scripts/uss-ref a ubuntu-setup-script 1.22+ ref?"
[[ -f $USS/tools/build-common.sh ]] || die "${USS}/tools/build-common.sh not found"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

export NGINX_BUILD_CI=1
export NGINX_BUILD_ROOT=$OUT
export NGINX_BUILD_CACHE=${NGINX_BUILD_CACHE:-$OUT/cache}
export NGINX_BUILD_COMMON=$USS/tools/build-common.sh
if [[ -f $USS/nginx-build.conf ]]; then
  export NGINX_BUILD_CONF=$USS/nginx-build.conf
fi

# The tool prints the tail of the failing step's log and its path itself.
if ! out=$(bash "$TOOL" build-only); then
  die "tools/nginx-build.sh build-only failed (NGINX_BUILD_CI=1; logs under ${OUT}/logs)"
fi
bin=$(printf '%s\n' "$out" | tail -n 1)

[[ $bin == "$OUT"/* ]] || die "tools/nginx-build.sh printed '${bin}', not a path under ${OUT}"
[[ -f $bin && -x $bin && ! -L $bin ]] || die "tools/nginx-build.sh printed '${bin}', which is not an executable file"
"$bin" -V >/dev/null 2>&1 || die "${bin} -V failed"
printf '%s\n' "$bin" > "$OUT/nginx-bin.path"
printf '%s\n' "$bin"
