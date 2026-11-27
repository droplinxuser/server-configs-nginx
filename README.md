# [Nginx Server Configs](https://github.com/h5bp/server-configs-nginx)

**Nginx Server Configs** is a collection of configuration files that can help
your server improve the website's performance and security, while also
ensuring that resources are served with the correct content-type and are
accessible, if needed, even cross-domain.

## Scope

This repository intentionally contains only **nginx** configuration.
PHP-FPM, server/system, MariaDB, Valkey and Elasticsearch configuration and
config-diff tooling live in
[`droplinxuser/ubuntu-setup-script`](https://github.com/droplinxuser/ubuntu-setup-script).
`setup.sh` there (1.22.0 and later) compiles nginx mainline from source
(binary under `/usr/local/lib/setup-nginx`, unit `nginx.service`) and syncs
this tree into `/etc/nginx`; this repository ships no deployer and does not
own PHP-FPM config.

## Branches

There is one branch, `main`: the nginx tree (nginx built from source,
`/etc/nginx`, logs in `/var/www/logs/nginx`) that ubuntu-setup-script
1.22.2+ downloads by default (`CONFIG_REPO_REF=main`).

Two tags keep older setup.sh releases working:

| Tag | Tree | For |
|---|---|---|
| `nginx` | the nginx tree as of 1.7.1 (frozen) | ubuntu-setup-script 1.22.0 and 1.22.1, whose default `CONFIG_REPO_REF` is `nginx` |
| `angie-final` | the last Angie tree (`angie.conf`, `/etc/angie`) | hosts kept on ubuntu-setup-script 1.21.x (`CONFIG_REPO_REF=angie-final`) |

A 1.21.x setup.sh that still downloads `main` refuses this tree (no
`angie.conf`) and keeps its Angie tree.  Update the setup.sh checkout before
`--optimize`: 1.22 migrates an Angie host to nginx.

## Layout on a host (1.22)

- `/etc/nginx/nginx.conf` is the main file.  `pid /run/nginx.pid` matches the
  build's `--pid-path` and the unit's `PIDFile=`; errors go to
  `/var/www/logs/nginx/error.log`.
- `fastcgi.conf` and `fastcgi_params` are shipped by the tree, because a
  source build installs only the binary.  They are upstream's files with
  `SERVER_SOFTWARE $fastcgi_server_software` (`http.d/server_software.conf`):
  `nginx` with no version, and `nginx/<version>` only on `admin.php`, so
  XenForo's admin Server environment report shows each host's nginx
  version.  WordPress detects nginx through it (permalinks without
  `/index.php`), and the value only reaches PHP.  CI enforces the line and
  the map.  `scgi_params` and `uwsgi_params` are not shipped: the
  build leaves those modules out.  `mime.types` stays as before.
- Brotli is compiled in statically, as ngx_brotli's filter module only
  (dynamic compression).  `http.d/brotli_conf` holds plain directives that
  setup.sh renders to `http.d/brotli.conf`; there is no `load_module` and no
  `modules-enabled` directory.
- No pre-compressed files are served (since tree 1.7.1 / ubuntu-setup-script
  1.22.1): the build compiles in neither `gzip_static` nor ngx_brotli's
  static module, and the tree has no `gzip_static`/`brotli_static` directive
  (CI refuses one).  gzip and Brotli compress responses on the fly.
  `h5bp/web_performance/pre-compressed_content_{gzip,brotli}.conf` are kept
  as empty, comment-only files so an existing include still loads.
- Open-file and umask limits live in the `nginx.service` unit that setup.sh
  writes (`LimitNOFILE=524288`, `UMask=0027`), so the tree no longer ships a
  systemd drop-in (`scripts/limit_nofile.conf`) or an `/etc/default` file
  (`scripts/etc_default_nginx`).
- `scripts/cloudflare.sh` (run from cron) rewrites
  `/etc/nginx/http.d/cloudflare.conf`, tests it with the compiled binary
  (`/usr/local/lib/setup-nginx/sbin/nginx -t`, the build-root binary by
  absolute path because cron's PATH has no `/usr/local/sbin`) and reloads a
  running `nginx.service`.
- TLS: the default and catch-all servers use the host's self-signed origin
  certificate in `/etc/nginx/ssl/default` (Cloudflare Full mode).
  Open-source nginx has no built-in ACME client of Angie's kind; the 1.22
  migration moves vhosts that used Angie's ACME to that certificate, and the
  `http.d/letsencrypt_conf` sample is gone.

## Local fork changes

This fork carries the nginx fixes validated with `setup.sh` 1.6.12 (names as
in ubuntu-setup-script 1.22):

- Hardware-aware tuning is owned by `ubuntu-setup-script/setup.sh` (the
  `--optimize` command, also used by the installers). Re-running
  `--optimize` re-applies the same profile on an existing host. The deployer
  (`deploy_nginx_tree()`) lives in setup.sh and only syncs the repository
  tree; setup.sh scales worker
  descriptors/connections, FastCGI buffers, TLS session
  cache, open-file caches, request-limit zones and HTTP cache sizes from the
  host's CPU count, RAM, free disk space and storage class.
- `worker_connections` is capped at 65k per worker (about 1M total on a
  16-core host) instead of 300k, cutting connection-slot memory from ~2 GB to
  ~0.5 GB; setup.sh lowers it further on small hosts.
- `resolver` uses the systemd-resolved stub `127.0.0.53` first, with public
  fallbacks. The old `127.0.0.1` first entry made dynamic lookups wait for a
  timeout on Ubuntu.
- The global 16 MB/s `limit_rate` cap is disabled; use per-vhost limits.
- There is **no FastCGI upstream keepalive cache**: every idle connection pins one
  PHP-FPM worker and the cache is per nginx worker, so a request on an nginx
  worker without a cached connection waits for the old 60 s
  `keepalive_timeout` (measured: 4-7 of 64 live /login requests took 60-112 s
  on a live XenForo origin). `fastcgi_keep_conn` is `off` in `h5bp/php*.conf` for the
  same reason; a Unix-socket connect is cheaper than the stalls.
- `h5bp/php*.conf` uses 128×32k FastCGI buffers instead of 512×32k, and fixes
  `PATH_TRANSLATED` so PHP-FPM does not return “Access denied”.
- TLS session tickets are disabled by default, and TLS 1.3 0-RTT early data is
  never enabled (no `ssl_early_data` opt-in or `Early-Data` header plumbing;
  origins sit behind Cloudflare, which does not send 0-RTT to the origin).
- `snippets/fastcgi-php.conf` is included (a source build does not install it).
- The safe optional configs are enabled as real `.conf` files: FastCGI cache,
  XenForo proxy/WebSocket/cache, proxy cache, the credential limiter and
  the referer map. Module-dependent snippets (Brotli, Naxsi, ngx_waf,
  sysguard) remain disabled.
- The only request limit is the credential limiter: login, registration and
  password-reset submissions, plus XenForo search (`POST /search/search`) and
  contact-form (`POST /misc/contact`) submissions, 20 a minute per address
  after a burst of 10, answered with `429`; loopback is exempt.  Search
  result pages and every other GET are never limited.  There are no generic
  per-IP GET/POST limits and no `limit_conn` (removed in 1.6.61).
- Compression is dynamic only (gzip and Brotli); `gzip_static` and
  `brotli_static` were removed in 1.7.1 with the static modules.
- The setup.sh deployer creates the `/home/*_cache` directories owned by
  `www-data`, removes old setup.sh/pre-refactor filenames, tests and reloads.
  Set `CONFIG_SOURCE_DIR=/path` to deploy a local checkout; `CONFIG_REPO_REF`
  selects a branch or tag.
- `scripts/cloudflare.sh` now validates both Cloudflare IP lists, writes
  `/etc/nginx/http.d/cloudflare.conf` atomically, and only reloads after
  `nginx -t` passes. A failed download leaves the previous file intact.
- `h5bp/wordpress_cache.conf` adds a cookie-aware guest page cache for
  WordPress (60 s, bypassed for logged-in users, POSTs, admin, cron and REST).
  The bypass decision is assembled with `map` in
  `http.d/wordpress_cache_map.conf` instead of `if` blocks. Measured on a
  16 vCPU VPS: ~242 -> ~9,972 req/s, p99 8.3 ms.
- The guest caches (WordPress, XenForo, Chevereto, Flarum) are default-deny
  for cookies: `$guest_cookie_unlisted` in `http.d/fastcgi_cache.conf` passes
  only analytics/consent, CDN/bot and the applications' own page-neutral
  guest cookies. Any other cookie, such as a plugin session or an SSO token,
  is rendered by PHP and never stored, so a cached page cannot leak one
  visitor's state to another.
- Removed the unused install script; building and installing nginx is owned
  by `setup.sh`, so this repository stays limited to configuration and config
  deployment.
- PHP-FPM pool templates, `custom_dan.ini` and `php-fpm-limits.conf` moved to
  `ubuntu-setup-script/configs/php/`. They are not nginx configuration and are
  no longer synced into `/etc/nginx/scripts`.
- Added `sample_php.conf` (generic/Lychee front controller) and
  `sample_node.conf` (Node proxy + WebSocket) templates.
- Template defects were repaired (duplicate SSL/proxy includes, `;;`, missing
  log directories, renamed proxy include). HTTP/3 moved to
  `h5bp/tls/http3.conf` because it is a server-block snippet, not a vhost.
- `conf.d/templates/example.com.conf` uses the embedded self-signed
  certificate by default; replace it with your real certificate.
- Moved out of this repository to `ubuntu-setup-script`:
  `basic_setup.sh`, `diff_configs.sh`, `cpufrequtils`, `dns_servers.conf`,
  `limits.conf`, `sysctl.conf`, and `mariadb_server.cnf`.

## Getting Started

Using the Nginx server configs repo directly has a few required steps to be able to work.

* [Nginx Beginners Guide](https://nginx.org/en/docs/beginners_guide.html)
* [Nginx Request Processing](https://nginx.org/en/docs/http/request_processing.html)


### Check `nginx.conf` settings

The first thing to check is that the `nginx.conf` file contains appropriate values for
your specific install.

Most specific variables are:

* `user`
* `error_log`
* `pid`
* `access_log`

### Nginx test and restart

* To verify Nginx config

  ```shell
  nginx -t
  ```

* To verify Nginx config with a custom file

  ```shell
  nginx -t -c nginx.conf
  ```

* To reload Nginx and apply the new config

  ```shell
  nginx -s reload
  ```

### Repository structure

This repository has the following structure:

```text
./
├── conf.d/
│   ├── default.conf
│   └── templates/
├── h5bp/
│   ├── basic.conf
│   ├── location/
│   └── .../
├── custom.d/
│   └── .../
├── mime.types
└── nginx.conf
```

* **`conf.d/`**

  This directory should contain all the `server` definitions.

  Except if they are dot prefixed or non `.conf` extension, all files in this
  directory are loaded automatically.

  * **`templates` folder**

    Files in this directory contain a `server` template for secure and non-secure
    hosts. They are intended to be copied in the `conf.d` directory with all
    `example.com` occurrences changed to the target host.

* **`h5bp/`**

  This directory contains config snippets (mixins) to be included as desired.

  There are two types of config files provided: individual config snippets and
  combined config files which provide convenient defaults.

  * **`basic.conf`**

    This file loads a small subset of the rules provided by this repository to add
    `expires` headers, allow cross-domain fonts and protect system files from web
    access.
    The `basic.conf` file includes the rules which are recommended to always be
    defined.

  * **`location/`**
  
    Files in this directory contain one or more `location` directives. They are
    intended to be loaded in the `server` context (or, in a nested `location` block).

* **`custom.d/`**

  This directory should contain all the custom `nginx.conf` configuration.

  Except if they are dot prefixed or non `.conf` extension, all files in this
  folder are loaded automatically.

* **`mime.types`**

  The `mime.types` file is responsible for mapping file extensions to MIME types.

* **`nginx.conf`**

  The main Nginx config file.


## Usage

### As a reference

To use as reference requires no special installation steps, download/checkout the
repository to a convenient location and adapt your existing Nginx configuration
incorporating the desired functionality from this repository.

Download the [latest release archive](https://github.com/h5bp/server-configs-nginx/releases/latest).

### Directly

To use directly, replace the Nginx config directory with this repository.
For example:

```shell
nginx -s stop
cd /etc
mv nginx nginx-previous
git clone https://github.com/h5bp/server-configs-nginx.git nginx
# install-specific edits
nginx
```

### Manage sites

```bash
cd /etc/nginx/conf.d
```

* Creating a new site

  ```bash
  cp templates/example.com.conf .actual-hostname.conf
  sed -i 's/example.com/actual-hostname/g' .actual-hostname.conf
  ```

* Enabling a site

  ```bash
  mv .actual-hostname.conf actual-hostname.conf
  ```

* Disabling a site

  ```bash
  mv actual-hostname.conf .actual-hostname.conf
  ```

```bash
nginx -s reload
```


## Support

 * nginx mainline 1.27.4+ as built by ubuntu-setup-script 1.22
   (`ssl_certificate_cache` needs 1.27.4; the tree also needs threads,
   http_v2, http_v3, realip, auth_basic, limit_req and the static ngx_brotli
   filter module; gzip_static and ngx_brotli's static module are not built
   since ubuntu-setup-script 1.22.1).  CI builds exactly that binary with the setup
   repository's `tools/nginx-build.sh` in CI mode, at the ref in
   `scripts/uss-ref`, and runs `nginx -t` on the tree and every template.
   Until the ubuntu-setup-script v1.22.1 tag exists, `scripts/uss-ref`
   stays at `v1.22.0`, so CI tests a binary that still has the static
   modules; `scripts/ci-guards.sh` rejects any `gzip_static`/`brotli_static`
   directive meanwhile.
 * Distribution nginx packages (Ubuntu 24.04's 1.24) and nginx.org's packages
   are not the target: they lack Brotli or `ssl_certificate_cache`, and they
   carry modules the lean build leaves out.


## Contributing

Anyone is welcome to [contribute](.github/CONTRIBUTING.md),
however, if you decide to get involved, please take a moment to review
the [guidelines](.github/CONTRIBUTING.md):

* [Bug reports](.github/CONTRIBUTING.md#bugs)
* [Feature requests](.github/CONTRIBUTING.md#features)
* [Pull requests](.github/CONTRIBUTING.md#pull-requests)


## Acknowledgements

[Nginx Server Configs](https://github.com/h5bp/server-configs-nginx) is
only possible thanks to all the awesome
[contributors](https://github.com/h5bp/server-configs-nginx/graphs/contributors)!


## License

The code is available under the [MIT license](LICENSE.txt).
