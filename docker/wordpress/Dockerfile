# Development WordPress: official image (latest stable WordPress, PHP 8.5, Apache)
# plus Xdebug, Redis extension, object cache drop-in, WP-CLI and Mailpit's sendmail.
FROM wordpress:php8.5-apache

# Apache/PHP and WP-CLI run as the host user, so files written to bind mounts
# (uploads) belong to the host user.
ARG HOST_UID
ARG HOST_GID
RUN set -eux; \
    test -n "${HOST_UID}" || { echo 'Build argument HOST_UID is required' >&2; exit 1; }; \
    test -n "${HOST_GID}" || { echo 'Build argument HOST_GID is required' >&2; exit 1; }; \
    groupmod --gid "${HOST_GID}" www-data; \
    usermod --uid "${HOST_UID}" --gid "${HOST_GID}" www-data

# Xdebug stays inactive unless XDEBUG_MODE enables it (compose.yaml defaults it to "off").
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends $PHPIZE_DEPS; \
    pecl install xdebug redis < /dev/null; \
    docker-php-ext-enable xdebug redis; \
    apt-get purge -y --auto-remove $PHPIZE_DEPS; \
    rm -rf /var/lib/apt/lists/* /tmp/pear; \
    php -m | grep -qx 'xdebug' ; \
    php -m | grep -qx 'redis'

COPY php/dev.ini "$PHP_INI_DIR/conf.d/zz-dev.ini"

# Object cache drop-in of the Redis Object Cache plugin (pinned, with checksum); the
# entrypoint copies it into wp-content when WP_OBJECT_CACHE is set. It uses the
# Redis extension above and needs no other file of the plugin.
ARG REDIS_CACHE_VERSION=3.0.0
ARG REDIS_CACHE_SHA256=7a03342d3defbe94cac8d0470b42dc1a1c34331b19c47205df20ceccd3c8f54a
ADD --checksum=sha256:${REDIS_CACHE_SHA256} https://downloads.wordpress.org/plugin/redis-cache.${REDIS_CACHE_VERSION}.zip /tmp/redis-cache.zip
RUN set -eux; \
    mkdir -p /usr/src/wp-dev-env; \
    php -r '$zip = new ZipArchive(); if ($zip->open("/tmp/redis-cache.zip") !== true) { exit(1); } $dropIn = $zip->getFromName("redis-cache/includes/object-cache.php"); if ($dropIn === false) { exit(1); } file_put_contents("/usr/src/wp-dev-env/object-cache.php", $dropIn);'; \
    rm /tmp/redis-cache.zip; \
    grep -q "Version: ${REDIS_CACHE_VERSION}" /usr/src/wp-dev-env/object-cache.php

COPY --from=wordpress:cli-php8.5 /usr/local/bin/wp /usr/local/bin/wp
COPY --from=axllent/mailpit:latest /mailpit /usr/local/bin/mailpit

# Document root from APACHE_DOCUMENT_ROOT at runtime (/var/www/html, or web/ of a Bedrock
# site repository), as the documentation of the official PHP image suggests.
ENV APACHE_DOCUMENT_ROOT=/var/www/html
RUN set -eux; \
    sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf; \
    grep -q 'APACHE_DOCUMENT_ROOT' /etc/apache2/sites-available/000-default.conf

COPY docker-entrypoint-dev.sh /usr/local/bin/docker-entrypoint-dev.sh
ENTRYPOINT ["docker-entrypoint-dev.sh"]
CMD ["apache2-foreground"]

# WP_CORE_PATH: where the core lies below the document root (empty, or /wp for Bedrock).
HEALTHCHECK --interval=2s --timeout=5s --start-period=60s --retries=30 \
    CMD curl -fsS -o /dev/null "http://localhost${WP_CORE_PATH:-}/readme.html" || exit 1
