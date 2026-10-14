# CLAUDE.md – wp-dev-env

General Docker development environment for WordPress themes and plugins; only Docker is needed on the host. It is for development only: tests, release tests and benchmarks run in a separate test environment (e.g. [wp-test-env](https://github.com/saijsaij/wp-test-env)), never against this site. It lives next to the projects it serves (the parent directory is the workspace, mounted as `/workspace`). The README is the user documentation; this file lists what matters when changing the environment.

<!-- Maintainers: keep this file under 200 lines. -->

## Rules

- **Stay general.** Nothing here refers to a specific theme, plugin or library: no project names in scripts, compose file, README or `.env.example`. Projects are configured only in the local `.env` (`WP_THEMES`, `WP_PLUGINS`, `WP_ACTIVE_THEME`, `WP_PACKAGE_LINKS`).
- **Never commit `.env` or `data/`.** Every variable a script reads is documented in `.env.example` and explained in the README; keep the three in sync.
- **Latest stable WordPress, never beta:** the image uses the floating `php8.5-apache` tag; automatic core updates stay disabled.
- **WordPress core is never persisted:** `/var/www/html` is a tmpfs in the WordPress container; only `data/db` and `data/uploads` persist.
- **The workspace is read-only in `wordpress`;** only `tools` writes to it, as the host user (`HOST_UID`/`HOST_GID`).
- **Relative symlinks must resolve everywhere:** the structure below `/workspace` matches the host, on the host and in every container.
- **Scripts are idempotent and fail loudly:** `set -euo pipefail`, clear `ERROR:` messages naming the file, variable or project at fault, no silent fallbacks.
- Verify the behavior of images, Docker Compose and WP-CLI in their documentation or source before relying on it; say clearly when something is not verified.
- Everything in this repository is English; other repositories are linked by GitHub URL.

## Commands

Run from this directory.

```sh
scripts/setup                                                          # idempotent: build, install, start, configure
scripts/reset                                                          # delete database and uploads, run setup again
docker compose exec -u www-data wordpress wp <command>                 # WP-CLI
docker compose run --rm tools composer <command> --working-dir=/workspace/<project>
docker compose run --rm tools npm --prefix /workspace/<project> <command>
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable scripts/*   # after changing scripts
```

## Definition of done for changes

- `shellcheck` reports nothing for `scripts/*`.
- `scripts/setup` succeeds twice in a row (second run changes nothing) and prints the running WordPress version; `scripts/reset` restores the defined state.
- The services named in the README are reachable through Traefik (`WP_URL`, Mailpit, dashboard); loopback requests of WordPress work (`scripts/setup` checks them).
- README, `.env.example` and `compose.yaml` describe the same variables and services.
