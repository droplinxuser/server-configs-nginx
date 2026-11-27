#!/usr/bin/env bash
# Static guards for the nginx tree (no root, no binary needed).
#
#  1. fastcgi.conf and fastcgi_params each set SERVER_SOFTWARE exactly once,
#     from $fastcgi_server_software (http.d/server_software.conf): "nginx"
#     by default (WordPress's $is_nginx / got_url_rewrite() need the name;
#     permalinks lose /index.php otherwise) and "nginx/$nginx_version" only
#     for admin.php (XenForo's Server environment report).  No
#     $nginx_version in the FastCGI files, no previous server's variables.
#  2. No trace of the previous web server outside the history documents
#     (CHANGELOG.md, README.md): its paths, binary or unit in a file that is
#     deployed to /etc/nginx would break a host after the old package is
#     purged.
#  3. The layout ubuntu-setup-script 1.22 expects: nginx.conf (not the old
#     main file), pid /run/nginx.pid (the unit's PIDFile=), logs under
#     /var/www/logs/nginx, and no load_module / modules-enabled (Brotli is
#     static), and no gzip_static / brotli_static directive: the build
#     compiles neither static module since ubuntu-setup-script 1.22.1, so
#     either directive would fail nginx -t on an updated host.
#  4. scripts/uss-ref names the ubuntu-setup-script ref CI builds nginx from:
#     a 40-hex commit SHA or a v* tag (the v1.22 branch until the release).
set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
fail=0
bad() { printf 'GUARD: %s\n' "$*" >&2; fail=1; }

# The old server's name, spelled so this file does not match itself.
OLD='an[g]ie'

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  mapfile -t files < <(git ls-files)
else
  mapfile -t files < <(find . -path ./.git -prune -o -type f -print | sed 's#^\./##')
fi

# 1. SERVER_SOFTWARE
for f in fastcgi.conf fastcgi_params; do
  if [[ ! -f $f ]]; then bad "$f is missing (a source build installs no package copy)"; continue; fi
  n_ok=$(grep -cE '^[[:space:]]*fastcgi_param[[:space:]]+SERVER_SOFTWARE[[:space:]]+\$fastcgi_server_software;[[:space:]]*$' "$f" || true)
  n_all=$(grep -cE '^[[:space:]]*fastcgi_param[[:space:]]+SERVER_SOFTWARE[[:space:]]' "$f" || true)
  [[ $n_ok == 1 && $n_all == 1 ]] || bad "$f: need exactly one 'fastcgi_param SERVER_SOFTWARE \$fastcgi_server_software;' (found ${n_ok} of ${n_all} SERVER_SOFTWARE lines)"
  if grep -niE '\$nginx_version|\$'"${OLD}"'_|'"${OLD}"'/' "$f"; then
    bad "$f: version or previous-server variable present"
  fi
done
# The map: bare "nginx" by default, the version on admin.php only.
m=http.d/server_software.conf
if [[ ! -f $m ]]; then
  bad "$m is missing (fastcgi.conf and fastcgi_params use \$fastcgi_server_software)"
else
  grep -qE '^[[:space:]]*map[[:space:]]+\$uri[[:space:]]+\$fastcgi_server_software[[:space:]]*\{' "$m" || bad "$m: no 'map \$uri \$fastcgi_server_software'"
  grep -qE '^[[:space:]]*default[[:space:]]+nginx;[[:space:]]*$' "$m" || bad "$m: the default must be 'nginx' (no version)"
  if [[ $(grep -cF 'nginx_version' "$m") != 1 ]] || ! grep -qF '"~(?:^|/)admin\.php$"   nginx/$nginx_version;' "$m"; then
    bad "$m: \$nginx_version only on the admin.php line"
  fi
fi

# 2. No trace of the previous server outside the history documents.
for f in "${files[@]}"; do
  case $f in
    CHANGELOG.md|README.md) continue ;;
  esac
  [[ -f $f ]] || continue
  if grep -nHi -E "$OLD" "$f"; then
    bad "$f mentions the previous web server"
  fi
done

# 3. Layout.
[[ -f nginx.conf ]] || bad "nginx.conf is missing"
for f in "${files[@]}"; do
  [[ $f == *.conf || $f == *_conf ]] || continue
  [[ -f $f ]] || continue
  if grep -nH -E '^[[:space:]]*(load_module|include[[:space:]]+[^;]*modules-enabled)' "$f"; then
    bad "$f: load_module/modules-enabled (Brotli is a static module in the 1.22 build)"
  fi
  if grep -nH -E '^[[:space:]]*(gzip_static|brotli_static)([[:space:]]|;)' "$f"; then
    bad "$f: gzip_static/brotli_static (neither static module is compiled in since ubuntu-setup-script 1.22.1)"
  fi
done
grep -qE '^[[:space:]]*pid[[:space:]]+/run/nginx\.pid;' nginx.conf || bad "nginx.conf: pid must be /run/nginx.pid (nginx.service PIDFile=, --pid-path)"
grep -qE '^[[:space:]]*error_log[[:space:]]+/var/www/logs/nginx/' nginx.conf || bad "nginx.conf: error_log must be under /var/www/logs/nginx"

# 4. Pinned ubuntu-setup-script ref.
if [[ ! -s scripts/uss-ref ]]; then
  bad "scripts/uss-ref is missing or empty"
else
  # An immutable ref only: a full commit SHA or a release tag (v*).  A branch
  # moves under CI, so a green run would not say which build was tested.
  # The workflow strips all whitespace; only surrounding whitespace is
  # tolerated here, so "v1.22 x" cannot pass as the tag "v1.22x".
  uss_ref=$(grep -m1 . scripts/uss-ref)
  uss_ref=${uss_ref#"${uss_ref%%[![:space:]]*}"}
  uss_ref=${uss_ref%"${uss_ref##*[![:space:]]}"}
  if [[ $(grep -c . scripts/uss-ref) != 1 ]]; then
    bad "scripts/uss-ref must hold exactly one ref on one line"
  elif [[ $uss_ref == v1.22 ]]; then
    # TODO(1.22.0 release): drop this exception and pin scripts/uss-ref to the
    # release tag (or its commit) once ubuntu-setup-script 1.22.0 is tagged;
    # until then CI builds from the 1.22 development branch.
    printf 'GUARD: note: scripts/uss-ref is the development branch v1.22 (allowed until the 1.22.0 release)\n' >&2
  elif ! [[ $uss_ref =~ ^[0-9a-f]{40}$ || $uss_ref =~ ^v[0-9][A-Za-z0-9._-]*$ ]]; then
    bad "scripts/uss-ref must be a 40-character commit SHA or a v* release tag (found '${uss_ref}')"
  fi
fi

if [[ $fail != 0 ]]; then exit 1; fi
echo "guards OK"
