# wp-dev-env

Docker development environment for WordPress themes and plugins. Only Docker is required on the host.

It is for developing: every project gets a **site** with its own database and uploads, which persist. One site runs at a time; switching takes one command. Tests, release tests and benchmarks belong in a test environment with fresh WordPress instances, such as [wp-test-env](https://github.com/saijsaij/wp-test-env), so they never change the development site.

- Latest stable WordPress on PHP 8.5 (official image), MariaDB, WP-CLI, Xdebug, Redis extension, optional persistent object cache (Valkey)
- Traefik on port 80 with host names: `<site>.localhost`, `mailpit.localhost`, `traefik.localhost`
- Mailpit catches all mail sent by WordPress
- Tools container with PHP 8.5 CLI, Composer, Node and Strauss

## Workspace

wp-dev-env lives next to the projects it serves. The parent directory is the workspace:

```
<workspace>/
├── wp-dev-env/        this repository
├── my-theme/          a theme checkout
├── my-library/        e.g. a Composer package used by my-theme
└── clients/
    └── my-plugin/     projects may be nested
```

The workspace is mounted as `/workspace` (read-only in the `wordpress` container). The themes and plugins of the active site are given as paths relative to the workspace and linked into `wp-content/themes` and `wp-content/plugins` under their last path segment (`clients/my-plugin` becomes `plugins/my-plugin`). Because the directory structure below `/workspace` matches the host, relative symlinks between checkouts resolve on the host and in every container.

`WP_PACKAGE_LINKS` (e.g. `vendor/library=my-library`) replaces a Composer package that a project installed from its lock file by a relative symlink to its checkout in the workspace, so changes to the library take effect immediately. `scripts/setup` sets the links in every project of the site after `composer install`; lock files and `composer.json` stay unchanged. Composer removes only the link (never the checkout) when it installs another version of the package.

## Sites

A site is one WordPress installation for one project: its own database, uploads, caches and authentication keys in `data/sites/<site>/`, its own projects, and its own host name `http://<site>.localhost` (so cookies and browser storage of different projects never mix). Configuration comes from two files, both local and never committed:

| File | Content |
|---|---|
| `config.env` | settings shared by all sites: workspace, ports, host names of Mailpit and Traefik, host user, database credentials, administrator, Xdebug (template: `config.env.example`) |
| `sites/<site>.env` | one site: `WP_SITE_TYPE`, `WP_SITE_ROOT`, `WP_THEMES`, `WP_PLUGINS`, `WP_ACTIVE_THEME`, `WP_PACKAGE_LINKS`, `WP_TITLE`, `WP_OBJECT_CACHE`, `WP_TABLE_PREFIX`, `WP_LIVE_URL` (template: `sites/example.env.example`) |

`scripts/setup <site>` checks both files, stops the previously active site (its data stays), writes `.env` from both files, the derived paths and URLs (`lib/site.sh`) and the site's keys and salts (`data/sites/<site>/salts.env`, generated once, so logins survive restarts), and sets the site up. Docker Compose reads the generated `.env`, so plain `docker compose` commands act on the active site. Every variable is required in its file; a missing, unknown or duplicate variable stops the setup with an error. A site needs no theme of its own: leave `WP_THEMES` empty and set `WP_ACTIVE_THEME` to a theme that ships with WordPress, such as `twentytwentyfive`.

### Site types

- **`vanilla`** runs the WordPress of the image: the core is copied to a tmpfs in `/var/www/html` on every start, the official entrypoint writes `wp-config.php`, and the projects of the site are linked into `wp-content`. `WP_SITE_ROOT` stays empty.
- **`bedrock`** runs a [Bedrock](https://roots.io/bedrock/) site repository (`WP_SITE_ROOT`, a path relative to the workspace) with its own core (`web/wp`), plugins and configuration from Composer. Apache serves `web/`; Bedrock reads its configuration (database, `WP_HOME`, `WP_SITEURL=<url>/wp`, `WP_ENV=development`, keys and salts) from the container's environment; WP-CLI runs in the repository and finds `wp-cli.yml` there. `scripts/setup` runs `composer install` in the repository before the projects.
  - Projects at `<root>/web/app/themes/<slug>` and `<root>/web/app/plugins/<slug>` belong to the repository (embedded, e.g. a theme built only for this site). They get `composer install`, package links and their build like every project, and run in development mode.
  - All other projects come from the workspace (e.g. a plugin you develop for several sites, or a test project): `scripts/setup` links them into `web/app/themes|plugins` of the repository, replacing a release Composer installed there. The repository must ignore these paths (`git check-ignore`; Bedrock ignores `web/app/plugins/*` already, themes need an entry in its `.gitignore`); otherwise the setup stops before it changes anything.
  - Uploads and caches are mounted at `web/app/uploads` and `web/app/cache` (the setup creates `web/app/cache`; Bedrock ignores it). The repository stays read-only in the container: WordPress cannot write `web/.htaccess`, so Apache sends every missing file to `index.php` itself, and plugins are installed with Composer, not in the admin. `WP_OBJECT_CACHE` must stay empty; require an object cache drop-in with Composer instead.
  - For a deployment, build every embedded theme and plugin with `composer release` in its directory and deploy its release instead of the source: the release command works in a subdirectory of the site repository.

## Usage

```sh
cp config.env.example config.env                  # adjust host UID/GID if needed
cp sites/example.env.example sites/my-site.env    # set the projects of the site
scripts/setup my-site     # idempotent: stop the other site, build, composer install, start, install WordPress, activate theme and plugins
scripts/reset my-site     # stop the site if it is active, delete its database and uploads, run setup again
scripts/import my-site data/dumps/live.sql.gz [--uploads data/dumps/uploads.tar.gz] [--keep-cron]   # replace the site's data with a dump
```

`scripts/setup` runs `composer install` in every project of the site that has a `composer.json`, then `npm ci` and `npm run build` (if the project defines it) in every project that has a `package.json` (a `package-lock.json` is required).

All services are reached through Traefik on host port 80 (must be free); `*.localhost` resolves to the loopback address in browsers and curl:

| URL | Service |
|---|---|
| `http://<site>.localhost` | WordPress of the active site (`WP_URL`); admin credentials come from `config.env` |
| `http://mailpit.localhost` | Mailpit web UI |
| `http://traefik.localhost` | Traefik dashboard |

Common commands:

```sh
docker compose exec -u www-data wordpress wp <command>                       # WP-CLI
docker compose run --rm tools composer <command> --working-dir=/workspace/<project>
docker compose run --rm tools npm --prefix /workspace/<project> <command>
docker compose run --rm tools npm --prefix /workspace/<project> run start   # watch: rebuild scripts on change
docker compose build --pull && docker compose up -d                          # update to the latest stable WordPress image
```

## Importing live data

`scripts/import <site> <dump.sql|dump.sql.gz> [--uploads <directory|archive.tar.gz|archive.tgz|archive.zip>] [--keep-cron]` replaces the database of a site with a dump, e.g. of the live site (a plain `mysqldump`/`mariadb-dump` of one database; dumps of MySQL 8 import as well):

1. It refuses dumps and uploads inside a Git work tree, except below `data/` (ignored here): live data contains personal data and must never end up in a repository. Keep them in `data/dumps/`.
2. It checks the dump before anything changes (in the `tools` container): it must contain `<WP_TABLE_PREFIX>options`, must not select or create a database (`USE`, `CREATE DATABASE`) and must not be a multisite database.
3. WP-Cron stays off for the imported data unless `--keep-cron` is given: scheduled events of a live site may call external services (payment, newsletters, APIs). The import marks the data (`data/sites/<site>/cron-disabled`); `scripts/setup` turns the mark into `DISABLE_WP_CRON`. Single events still run with `wp cron event run <hook>`; the next import decides again, `scripts/reset` removes the mark with the data.
4. It runs `scripts/setup <site>` and replaces the database.
5. `wp search-replace` replaces `WP_LIVE_URL` (with `https://` and `http://`, also JSON-escaped as in block attributes) by the local URL in all tables with the prefix; GUIDs stay unchanged.
6. The administrator from `config.env` gets its password and the role administrator, or is created. The theme and plugins of the site file are activated; rewrite rules and the object cache are flushed. Permalinks of the imported data stay (`scripts/setup` sets them only on a fresh installation).
7. With `--uploads`, the uploads of the site are replaced by the directory or archive (its content is the content of `wp-content/uploads`; a single top-level directory `uploads` is entered). Without it, the uploads stay unchanged.

Whenever `WP_LIVE_URL` is set, requests for files below `/wp-content/uploads/` that do not exist locally redirect (302) to the same path on the live site, so a site works without copying all uploads.

Mail always goes to Mailpit.

## Services

| Service | Purpose |
|---|---|
| `traefik` | Reverse proxy on host port 80; routes by host name (`docker/traefik/dynamic.yml`, host names from `.env`). |
| `wordpress` | Official `wordpress:php8.5-apache` image plus Xdebug, Redis extension, the object cache drop-in of [Redis Object Cache](https://wordpress.org/plugins/redis-cache/) (pinned with checksum), WP-CLI and Mailpit's sendmail; the document root comes from `APACHE_DOCUMENT_ROOT` (`/var/www/html`, or `web/` of a Bedrock site). |
| `db` | MariaDB (LTS). Port not exposed. |
| `tools` | PHP 8.5 CLI with `zip`, GD and Imagick (GD writes JPEG, PNG, WebP and AVIF, Imagick all but AVIF), Composer, Node and [Strauss](https://github.com/BrianHenryIE/strauss) (pinned phar with checksum, for PHP namespace prefixing) (profile `tools`, used via `docker compose run`). |
| `mail` | Mailpit; receives all mail sent by WordPress. |
| `valkey` | Valkey as persistent object cache (profile `objectcache`, started by `scripts/setup` when `WP_OBJECT_CACHE=valkey`); nothing is persisted. |

## Rules

- **WordPress core is never persisted** in a vanilla site: `/var/www/html` is a tmpfs, so every container start copies the core fresh from the image. A Bedrock site uses the core its repository requires. Only the data of each site (`data/sites/<site>/`: database, uploads, caches, keys and salts) persist.
- **Always the latest stable WordPress** in vanilla sites, never beta: the image uses the floating `php8.5-apache` tag. Update with `docker compose build --pull`. Automatic core updates are disabled.
- **The workspace is read-only in `wordpress`.** Project code cannot write into its own directory; only `tools` can write to the workspace.
- **Containers write as the host user** (`HOST_UID`/`HOST_GID`), so `data/`, `vendor/` and `node_modules/` stay owned by the host user.
- **Loopback requests work.** WordPress calls itself at `WP_URL` (WP-Cron, Site Health). Inside the container `WP_HOST` maps to `127.0.0.1` (bypassing Traefik) and Apache listens on port 80, so `HTTP_PORT` must be 80; `scripts/setup` fails if loopback requests do not work.
- **Live data stays local.** Dumps and uploads of live sites belong in `data/` (never committed); `scripts/import` refuses them inside any other Git work tree.
- **One site at a time.** All sites share the Compose project `wp-dev-env`; `scripts/setup <site>` stops the active one first.
- **Xdebug** is installed but only active when `XDEBUG_MODE` in `config.env` is not `off`.
- **Persistent object cache** only with `WP_OBJECT_CACHE=valkey` in the site file: `scripts/setup` then starts `valkey` (profile `objectcache`) and the entrypoint copies the drop-in to `wp-content/object-cache.php`. Run `scripts/setup` after changing the variable; it recreates the containers and prints the object cache type. Without a reachable Valkey the drop-in stops WordPress with an error instead of falling back silently. For a plain `docker compose up`, add `--profile objectcache`.
