# [Nginx Server Configs](https://github.com/h5bp/server-configs-nginx)

[![Server CI](https://github.com/h5bp/server-configs-nginx/actions/workflows/server.yml/badge.svg)](https://github.com/h5bp/server-configs-nginx/actions/workflows/server.yml)

**Nginx Server Configs** is a collection of configuration files that can help
your server improve the website's performance and security, while also
ensuring that resources are served with the correct content-type and are
accessible, if needed, even cross-domain.

## Scope

This repository intentionally contains only **Angie/Nginx and PHP-FPM**
configuration. Server/system/MariaDB configuration, the legacy basic-setup
script and config-diff tooling live in
[`droplinxuser/ubuntu-setup-script`](https://github.com/droplinxuser/ubuntu-setup-script).

## Local fork changes

This fork carries the Angie/Nginx fixes validated with `setup.sh` 1.6.8:

- `scripts/auto_tune.sh` runs after each config sync and scales worker
  descriptors/connections, FastCGI buffers, upstream keepalive, TLS session
  cache, open-file caches, request-limit zones and HTTP cache sizes from the
  host's CPU count, RAM, free disk space and storage class. The repository is
  no longer tuned for one fixed 16-core machine.
- `worker_connections` is capped at 65k per worker (about 1M total on a
  16-core host) instead of 300k, cutting connection-slot memory from ~2 GB to
  ~0.5 GB; auto_tune lowers it further on small hosts.
- `resolver` uses the systemd-resolved stub `127.0.0.53` first, with public
  fallbacks. The old `127.0.0.1` first entry made dynamic lookups wait for a
  timeout on Ubuntu.
- The global 16 MB/s `limit_rate` cap is disabled; use per-vhost limits.
- FastCGI upstream keepalive is 64 (was 3).
- `h5bp/php*.conf` uses 128×32k FastCGI buffers instead of 512×32k, and fixes
  `PATH_TRANSLATED` so PHP-FPM does not return “Access denied”.
- TLS session tickets and 0-RTT early data are disabled by default.
- `snippets/fastcgi-php.conf` is included (Angie does not ship it).
- The safe optional configs are enabled as real `.conf` files: FastCGI cache,
  XenForo proxy/WebSocket/cache, proxy cache, per-IP rate limiting and the
  referer map. Module-dependent snippets (Brotli, zstd, Naxsi, ngx_waf, trim,
  sysguard) remain disabled.
- Rate limiting exempts loopback, uses 100 GET/s and 30 POST/HEAD/s for
  external clients, and returns `429` instead of a connection-dropping `444`.
- `gzip_static on` is enabled; pre-compressed assets are served when present.
- `scripts/nginx_conf.sh` creates the `/home/*_cache` directories owned by
  `www-data`, removes old setup.sh/pre-refactor filenames, tests and reloads.
  Set `CONFIG_SOURCE_DIR=/path` to deploy a local checkout; `CONFIG_REPO_REF`
  selects a branch or tag.
- `scripts/cloudflare.sh` now validates both Cloudflare IP lists, writes
  `/etc/angie/http.d/cloudflare.conf` atomically, and only reloads after
  `angie -t` passes. A failed download leaves the previous file intact.
- `h5bp/wordpress_cache.conf` adds a cookie-aware guest page cache for
  WordPress (60 s, bypassed for logged-in users, POSTs, admin, cron and REST).
  The bypass decision is assembled with `map` in
  `http.d/wordpress_cache_map.conf` instead of `if` blocks. Measured on a
  16 vCPU VPS: ~242 -> ~9,972 req/s, p99 8.3 ms.
- Removed the unused `scripts/install_angie.sh`; package installation is owned
  by `setup.sh`, so this repository stays limited to configuration and config
  deployment.
- PHP-FPM pool templates (`scripts/www_8*.conf`), `scripts/custom_dan.ini` and
  `scripts/php-fpm-limits.conf` are the source of truth used by `setup.sh`.
  Add `scripts/www_<ver>.conf` when adding a new PHP version.
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

 * Nginx v**1.8.0**+


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
