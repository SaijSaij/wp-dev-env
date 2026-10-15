# Shared functions of scripts/: site names, the variables derived from a site, and
# stopping the containers. Sourced, never executed.
# shellcheck shell=bash
# shellcheck disable=SC2034 # the variables are used by the scripts that source this file

# Variables of config.env (shared by all sites) and of a site file; all are required.
CONFIG_KEYS=(WORKSPACE_DIR HTTP_PORT MAILPIT_HOST TRAEFIK_HOST HOST_UID HOST_GID
    DB_NAME DB_USER DB_PASSWORD WP_ADMIN_USER WP_ADMIN_PASSWORD WP_ADMIN_EMAIL XDEBUG_MODE)
SITE_KEYS=(WP_SITE_TYPE WP_SITE_ROOT WP_THEMES WP_PLUGINS WP_ACTIVE_THEME WP_PACKAGE_LINKS
    WP_TITLE WP_OBJECT_CACHE WP_TABLE_PREFIX WP_LIVE_URL)
# Authentication keys and salts of a site, generated once (data/sites/<site>/salts.env).
SALT_KEYS=(AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY AUTH_SALT SECURE_AUTH_SALT
    LOGGED_IN_SALT NONCE_SALT)
# Variables derive_site_variables sets; scripts/setup writes them to .env.
DERIVED_KEYS=(WP_SITE WP_HOST WP_URL WP_SITEURL WP_CORE_PATH WP_DOCROOT WP_WORKDIR
    WP_UPLOADS_DIR WP_CACHE_DIR WP_DISABLE_CRON)

# check_site_name <site>
check_site_name() {
    if [[ ! "$1" =~ ^[a-z][a-z0-9-]*$ ]]; then
        echo "ERROR: invalid site name '$1'; expected lowercase letters, digits and hyphens, starting with a letter." >&2
        exit 1
    fi
}

# load_site <site>: loads config.env and sites/<site>.env (exported) and derives the
# remaining variables. The files must have been checked (scripts/setup) or be checked later.
load_site() {
    local site="$1"
    set -a
    # shellcheck source=/dev/null
    source config.env
    # shellcheck source=/dev/null
    source "sites/${site}.env"
    set +a
    derive_site_variables "${site}"
    ensure_salts "${site}"
    set -a
    # shellcheck source=/dev/null
    source "data/sites/${site}/salts.env"
    set +a
}

# ensure_salts <site>: random keys and salts of the site, kept with its data, so logins
# survive restarts; scripts/reset creates new ones. Letters and digits only, so they
# need no quoting in .env. Without them WordPress falls back to null constants, which
# PHP 8.5 reports as deprecated in wp_salt() (Bedrock), or the official image makes new
# ones on every start (vanilla).
ensure_salts() {
    local file="data/sites/$1/salts.env" key value
    if [[ -f "${file}" ]]; then
        return
    fi
    mkdir -p "data/sites/$1"
    for key in "${SALT_KEYS[@]}"; do
        # A fixed amount of random bytes (no SIGPIPE under pipefail), about 970 usable.
        value="$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9')"
        echo "${key}=${value:0:64}"
    done > "${file}.tmp"
    mv "${file}.tmp" "${file}"
}

# derive_site_variables <site>: host and URLs, the paths in the WordPress container
# for both site types, and whether WP-Cron is off for imported data.
derive_site_variables() {
    local site="$1" content
    WP_SITE="${site}"
    WP_HOST="${site}.localhost"
    WP_URL="http://${WP_HOST}"
    case "${WP_SITE_TYPE:-}" in
        vanilla)
            # Official image: core, wp-config.php and wp-content on a tmpfs in /var/www/html.
            WP_CORE_PATH=""
            WP_DOCROOT=/var/www/html
            WP_WORKDIR=/var/www/html
            content=/var/www/html/wp-content
            ;;
        bedrock)
            # The site repository: core in web/wp (Composer), content in web/app.
            WP_CORE_PATH=/wp
            WP_DOCROOT="/workspace/${WP_SITE_ROOT}/web"
            WP_WORKDIR="/workspace/${WP_SITE_ROOT}"
            content="${WP_DOCROOT}/app"
            ;;
        *)
            echo "ERROR: WP_SITE_TYPE '${WP_SITE_TYPE:-}' in sites/${site}.env must be vanilla or bedrock." >&2
            exit 1
            ;;
    esac
    WP_SITEURL="${WP_URL}${WP_CORE_PATH}"
    WP_UPLOADS_DIR="${content}/uploads"
    WP_CACHE_DIR="${content}/cache"
    # scripts/import marks imported data whose WP-Cron stays off (DISABLE_WP_CRON).
    if [[ -f "data/sites/${site}/cron-disabled" ]]; then
        WP_DISABLE_CRON=1
    else
        WP_DISABLE_CRON=0
    fi
    export "${DERIVED_KEYS[@]}"
}

# stop_containers: removes all containers of the Compose project (any site). Uses the
# Compose labels, so it works whatever .env holds.
stop_containers() {
    local ids
    ids="$(docker ps -aq --filter label=com.docker.compose.project=wp-dev-env)"
    if [[ -n "${ids}" ]]; then
        # shellcheck disable=SC2086 # one ID per word
        docker rm -f ${ids} > /dev/null
    fi
}
