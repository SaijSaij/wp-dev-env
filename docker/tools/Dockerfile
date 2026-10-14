# Build tools: PHP 8.5 CLI (with zip, GD and Imagick), Composer, Node and Strauss (PHP namespace prefixing).
FROM php:8.5-cli

# GD and Imagick, like the official WordPress image, for build tools that process images (e.g. image
# variants of a theme's assets): GD writes JPEG, PNG, WebP and AVIF; Imagick writes JPEG, PNG and WebP
# (it reads AVIF, but Debian's libheif has no AVIF encoder).
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends git unzip libzip-dev \
        libavif-dev libfreetype6-dev libjpeg-dev libpng-dev libwebp-dev libmagickwand-dev; \
    docker-php-ext-configure gd --with-avif --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install zip gd; \
    pecl install imagick < /dev/null; \
    docker-php-ext-enable imagick; \
    rm -rf /var/lib/apt/lists/* /tmp/pear; \
    php -r '$i = imagecreatetruecolor(1, 1); exit(imageavif($i, "/tmp/p.avif") && imagewebp($i, "/tmp/p.webp") ? 0 : 1);'; \
    php -r 'foreach (["webp", "jpeg", "png"] as $f) { $i = new Imagick(); $i->newImage(1, 1, "white"); $i->setImageFormat($f); $i->getImageBlob(); }'; \
    rm -f /tmp/p.avif /tmp/p.webp

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# Strauss as phar, pinned and verified (https://github.com/BrianHenryIE/strauss/releases).
ARG STRAUSS_VERSION=0.31.1
ARG STRAUSS_SHA256=17dc2baf27b9a3f52834e3db729c8365d8915a80e37a087d253cf705387aa887
ADD --checksum=sha256:${STRAUSS_SHA256} https://github.com/BrianHenryIE/strauss/releases/download/${STRAUSS_VERSION}/strauss.phar /usr/local/bin/strauss
RUN set -eux; \
    chmod 0755 /usr/local/bin/strauss; \
    strauss --version

COPY --from=node:24-trixie-slim /usr/local/bin/node /usr/local/bin/node
COPY --from=node:24-trixie-slim /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN set -eux; \
    ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm; \
    ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx; \
    node --version; \
    npm --version

# Shared cache directory (named volume); writable for the host user the container runs as.
RUN mkdir -m 1777 /cache
ENV HOME=/tmp \
    COMPOSER_CACHE_DIR=/cache/composer \
    npm_config_cache=/cache/npm

WORKDIR /workspace
