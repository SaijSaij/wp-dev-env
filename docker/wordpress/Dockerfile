# Development WordPress: official image (latest stable WordPress, PHP 8.5, Apache)
# plus Xdebug, Redis extension, WP-CLI and Mailpit's sendmail.
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

COPY --from=wordpress:cli-php8.5 /usr/local/bin/wp /usr/local/bin/wp
COPY --from=axllent/mailpit:latest /mailpit /usr/local/bin/mailpit

COPY docker-entrypoint-dev.sh /usr/local/bin/docker-entrypoint-dev.sh
ENTRYPOINT ["docker-entrypoint-dev.sh"]
CMD ["apache2-foreground"]

HEALTHCHECK --interval=2s --timeout=5s --start-period=60s --retries=30 \
    CMD curl -fsS -o /dev/null http://localhost/readme.html || exit 1
