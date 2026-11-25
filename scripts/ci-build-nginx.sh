#!/usr/bin/env bash
# Build the nginx binary CI tests this tree with: ubuntu-setup-script's own
# tools/nginx-build.sh in its CI mode (NGINX_BUILD_CI=1), at the
# ubuntu-setup-script ref pinned in scripts/uss-ref.
#
# CI mode keeps the configure module set of the shipped build (static
# ngx_brotli, http_v3, realip, gzip_static, threads, auth_basic, limit_req,
# the same left-out modules) and the branding patch, and drops what only
# matters on a host or costs CI minutes: no LTO, no BOLT, no -march=native,
# no unit, no activation.  Sharing the tool means the CI binary and the
# fleet's binary cannot drift apart in which directives they accept.
#
# Usage (root, on a throwaway runner):
#   ci-build-nginx.sh USS_DIR OUT_DIR
#     USS_DIR  checkout of ubuntu-setup-script at the pinned ref
#     OUT_DIR  build root (NGINX_BUILD_ROOT); the binary's path is printed
#              on the last line and written to OUT_DIR/nginx-bin.path
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

if ! bash "$TOOL" build; then
  # The tool keeps its logs under ROOT/logs (1.22); show the end of the newest.
  log=$(find "$OUT" -type f -name '*.log' -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n 1 | cut -d' ' -f2-)
  if [[ -n $log ]]; then
    printf '%s\n' "--- tail of ${log}" >&2
    tail -n 80 "$log" >&2 || true
  fi
  die "tools/nginx-build.sh build failed (NGINX_BUILD_CI=1)"
fi

# Where the verified binary lands: the staging slot of the build-only step,
# else the installed slot; any other layout is searched for as a last resort.
bin=""
for c in "$OUT/staging/sbin/nginx" "$OUT/sbin/nginx" "$OUT/build/nginx"; do
  if [[ -x $c && ! -L $c ]]; then bin=$c; break; fi
done
if [[ -z $bin ]]; then
  bin=$(find "$OUT" -path "$OUT/cache" -prune -o -type f -name nginx -perm -u+x -print 2>/dev/null | head -n 1)
fi
[[ -n $bin ]] || die "the build finished but no nginx binary was found under ${OUT}"
"$bin" -V >/dev/null 2>&1 || die "${bin} -V failed"
printf '%s\n' "$bin" > "$OUT/nginx-bin.path"
printf '%s\n' "$bin"
