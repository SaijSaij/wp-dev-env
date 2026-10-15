#!/bin/sh
# Links the configured workspace projects into the (tmpfs) WordPress directory,
# installs the object cache drop-in if WP_OBJECT_CACHE asks for it,
# then hands over to the official entrypoint, which copies the WordPress core
# from the image.
set -eu

wp_content=/var/www/html/wp-content

# link_projects <themes|plugins> <comma-separated paths relative to the workspace>
# Each project is linked under its last path segment (its slug).
link_projects() {
    kind="$1"
    paths="$2"
    variable="WP_$(echo "${kind}" | tr '[:lower:]' '[:upper:]')"

    mkdir -p "${wp_content}/${kind}"
    chown www-data:www-data "${wp_content}/${kind}"

    for path in $(echo "${paths}" | tr ',' ' '); do
        case "/${path}/" in
            //* | */./* | */../*)
                echo "ERROR: invalid project path '${path}' in ${variable}; expected a path relative to the workspace, without '.' or '..'." >&2
                exit 1
                ;;
        esac
        if [ ! -d "/workspace/${path}" ]; then
            echo "ERROR: /workspace/${path} not found. Check ${variable} in the site file and WORKSPACE_DIR in config.env." >&2
            exit 1
        fi
        slug="$(basename "${path}")"
        # wp-content is a fresh tmpfs, so an existing link means two projects with the same slug.
        if [ -e "${wp_content}/${kind}/${slug}" ] || [ -L "${wp_content}/${kind}/${slug}" ]; then
            echo "ERROR: ${variable} links two projects as ${kind}/${slug}." >&2
            exit 1
        fi
        ln -s "/workspace/${path}" "${wp_content}/${kind}/${slug}"
        chown -h www-data:www-data "${wp_content}/${kind}/${slug}"
        echo "Linked ${kind}/${slug} -> /workspace/${path}" >&2
    done
}

mkdir -p "${wp_content}"
chown www-data:www-data "${wp_content}"
link_projects themes "${WP_THEMES}"
link_projects plugins "${WP_PLUGINS}"

case "${WP_OBJECT_CACHE}" in
    '')
        ;;
    valkey)
        cp /usr/src/wp-dev-env/object-cache.php "${wp_content}/object-cache.php"
        chown www-data:www-data "${wp_content}/object-cache.php"
        echo "Installed object-cache.php (Valkey at ${WP_REDIS_HOST})" >&2
        ;;
    *)
        echo "ERROR: invalid WP_OBJECT_CACHE '${WP_OBJECT_CACHE}'; expected empty or 'valkey'." >&2
        exit 1
        ;;
esac

exec docker-entrypoint.sh "$@"
