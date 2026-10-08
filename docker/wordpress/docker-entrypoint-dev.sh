#!/bin/sh
# Links the configured workspace projects into the (tmpfs) WordPress directory,
# then hands over to the official entrypoint, which copies the WordPress core
# from the image.
set -eu

wp_content=/var/www/html/wp-content

# link_projects <themes|plugins> <comma-separated directory names>
link_projects() {
    kind="$1"
    names="$2"

    mkdir -p "${wp_content}/${kind}"
    chown www-data:www-data "${wp_content}/${kind}"

    for name in $(echo "${names}" | tr ',' ' '); do
        case "${name}" in
            */* | . | ..)
                echo "ERROR: invalid project name '${name}' in WP_$(echo "${kind}" | tr '[:lower:]' '[:upper:]'); expected a directory name in the workspace." >&2
                exit 1
                ;;
        esac
        if [ ! -d "/workspace/${name}" ]; then
            echo "ERROR: /workspace/${name} not found. Check WP_$(echo "${kind}" | tr '[:lower:]' '[:upper:]') and WORKSPACE_DIR in .env." >&2
            exit 1
        fi
        ln -sfn "/workspace/${name}" "${wp_content}/${kind}/${name}"
        chown -h www-data:www-data "${wp_content}/${kind}/${name}"
        echo "Linked ${kind}/${name} -> /workspace/${name}" >&2
    done
}

mkdir -p "${wp_content}"
chown www-data:www-data "${wp_content}"
link_projects themes "${WP_THEMES}"
link_projects plugins "${WP_PLUGINS}"

exec docker-entrypoint.sh "$@"
