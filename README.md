# wp-dev-env

Docker development environment for WordPress themes and plugins. Only Docker is required on the host.

- Latest stable WordPress on PHP 8.5 (official image), MariaDB, WP-CLI, Xdebug, Redis extension
- Traefik on port 80 with host names: `wp-dev.localhost`, `mailpit.localhost`, `traefik.localhost`
- Mailpit catches all mail sent by WordPress
- Tools container with PHP 8.5 CLI, Composer and Node

## Workspace

wp-dev-env lives next to the projects it serves. The parent directory is the workspace:

```
<workspace>/
├── wp-dev-env/        this repository
├── my-theme/          a theme checkout
├── my-plugin/         a plugin checkout
└── my-library/        e.g. a Composer path repository used by my-theme
```

The workspace is mounted as `/workspace` (read-only in the `wordpress` container). Themes and plugins listed in `.env` are linked into `wp-content/themes` and `wp-content/plugins`. Because the directory structure below `/workspace` matches the host, relative symlinks between checkouts (such as Composer `path` repositories) resolve on the host and in every container.

## Usage

```sh
cp .env.example .env      # set WP_THEMES, WP_PLUGINS, WP_ACTIVE_THEME; adjust host UID/GID if needed
scripts/setup             # idempotent: build, composer install, start, install WordPress, activate theme and plugins
scripts/reset             # stop everything, delete database and uploads, run setup again
```

`scripts/setup` runs `composer install` in every listed project that has a `composer.json`, then `npm ci` and `npm run build` (if the project defines it) in every project that has a `package.json` (a `package-lock.json` is required).

All services are reached through Traefik on host port 80 (must be free); `*.localhost` resolves to the loopback address in browsers and curl:

| URL | Service |
|---|---|
| `http://wp-dev.localhost` | WordPress (`WP_URL`); admin credentials come from `.env` |
| `http://mailpit.localhost` | Mailpit web UI |
| `http://traefik.localhost` | Traefik dashboard |

Common commands:

```sh
docker compose exec -u www-data wordpress wp <command>                       # WP-CLI
docker compose run --rm tools composer <command> --working-dir=/workspace/<project>
docker compose run --rm tools npm --prefix /workspace/<project> <command>
docker compose run --rm tools npm --prefix /workspace/<project> run start   # watch: rebuild scripts on change
docker compose run --rm e2e npm --prefix /workspace/<project> run test:e2e    # browser tests (profile e2e)
docker compose build --pull && docker compose up -d                          # update to the latest stable WordPress image
```

## Services

| Service | Purpose |
|---|---|
| `traefik` | Reverse proxy on host port 80; routes by host name (`docker/traefik/dynamic.yml`, host names from `.env`). |
| `wordpress` | Official `wordpress:php8.5-apache` image plus Xdebug, Redis extension, WP-CLI and Mailpit's sendmail. |
| `db` | MariaDB (LTS). Port not exposed. |
| `tools` | PHP 8.5 CLI, Composer and Node (profile `tools`, used via `docker compose run`). |
| `mail` | Mailpit; receives all mail sent by WordPress. |
| `e2e` | Official Playwright image for the browser tests of the projects (profile `e2e`, used via `docker compose run`). Reads the workspace read-only and writes results to `data/e2e`. |

## Rules

- **WordPress core is never persisted.** `/var/www/html` is a tmpfs, so every container start copies the core fresh from the image. Only the database (`data/db`) and uploads (`data/uploads`) persist.
- **Always the latest stable WordPress**, never beta: the image uses the floating `php8.5-apache` tag. Update with `docker compose build --pull`. Automatic core updates are disabled.
- **The workspace is read-only in `wordpress`.** Project code cannot write into its own directory; only `tools` can write to the workspace.
- **Containers write as the host user** (`HOST_UID`/`HOST_GID`), so `data/`, `vendor/` and `node_modules/` stay owned by the host user.
- **Loopback requests work.** WordPress calls itself at `WP_URL` (WP-Cron, Site Health). Inside the container `WP_HOST` maps to `127.0.0.1` (bypassing Traefik) and Apache listens on port 80, so `HTTP_PORT` must be 80; `scripts/setup` fails if loopback requests do not work.
- **Xdebug** is installed but only active when `XDEBUG_MODE` in `.env` is not `off`.
- **Browser tests reach WordPress through Traefik.** Traefik carries `WP_HOST` as network alias, so tools in the `e2e` container (Node) resolve `WP_URL`. Browsers resolve `*.localhost` to the loopback address themselves; projects pass `E2E_BROWSER_HOST_RULES` to Chromium (`--host-resolver-rules`). `PLAYWRIGHT_VERSION` must match the `@playwright/test` version of the projects.
