# [Nginx Server Configs](https://github.com/h5bp/server-configs-nginx)

[![Server CI](https://github.com/h5bp/server-configs-nginx/actions/workflows/server.yml/badge.svg)](https://github.com/h5bp/server-configs-nginx/actions/workflows/server.yml)

**Nginx Server Configs** is a collection of configuration files that can help
your server improve the website's performance and security, while also
ensuring that resources are served with the correct content-type and are
accessible, if needed, even cross-domain.

## Local fork changes

This fork carries the Angie/Nginx fixes validated with `setup.sh` 1.4.0:

- `worker_connections` is 65k (about 1M total on a 16-core host) instead of
  300k, cutting worker connection-slot memory from ~2 GB to ~0.5 GB.
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
  `www-data` before testing/reloading.
- Template defects were repaired (duplicate SSL/proxy includes, `;;`, missing
  log directories, renamed proxy include). HTTP/3 moved to
  `h5bp/tls/http3.conf` because it is a server-block snippet, not a vhost.
- `conf.d/templates/example.com.conf` uses the embedded self-signed
  certificate by default; replace it with your real certificate.

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
