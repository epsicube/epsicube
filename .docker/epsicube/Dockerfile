ARG FRANKENPHP_VERSION=1.12.7
ARG PHP_VERSION=8.5

#-------------------------------------------------------CUSTOM CADDY BUILD----------------------------------------------
# FrankenPHP ships Mercure 0.x, the Laravel "mercure" driver speaks Mercure 1.0
FROM dunglas/frankenphp:${FRANKENPHP_VERSION}-builder-php${PHP_VERSION}-trixie AS caddy-builder
ARG MERCURE_VERSION=v1.0.2
COPY --from=caddy:builder /usr/bin/xcaddy /usr/bin/xcaddy
RUN GOTOOLCHAIN=auto \
    CGO_ENABLED=1 \
    XCADDY_SETCAP=1 \
    XCADDY_GO_BUILD_FLAGS="-ldflags='-w -s' -tags=nobadger,nomysql,nopgx" \
    CGO_CFLAGS="$(php-config --includes)" \
    CGO_LDFLAGS="$(php-config --ldflags) $(php-config --libs)" \
    xcaddy build \
        --output /usr/local/bin/frankenphp \
        --with github.com/dunglas/frankenphp=./ \
        --with github.com/dunglas/frankenphp/caddy=./caddy/ \
        --with github.com/dunglas/caddy-cbrotli \
        --with github.com/dunglas/mercure=github.com/dunglas/mercure@${MERCURE_VERSION} \
        --with github.com/dunglas/mercure/caddy@${MERCURE_VERSION}

FROM dunglas/frankenphp:${FRANKENPHP_VERSION}-php${PHP_VERSION}-trixie AS base

ENV TZ=UTC
ENV DEBIAN_FRONTEND=noninteractive

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN echo "Acquire::http::Pipeline-Depth 0;" > /etc/apt/apt.conf.d/99custom && \
    echo "Acquire::http::No-Cache true;" >> /etc/apt/apt.conf.d/99custom && \
    echo "Acquire::BrokenProxy    true;" >> /etc/apt/apt.conf.d/99custom

# Install dependencies
RUN apt-get update && \
    apt-get install -y curl sqlite3 postgresql-client procps && \
    apt-get -y autoremove && apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*


# Add NodeSource repository and install Node.js
ARG NODE_VERSION=24
RUN curl -fsSL https://deb.nodesource.com/setup_$NODE_VERSION.x | bash - \
    && apt-get install -y nodejs \
    && corepack enable \
    && npx playwright install-deps \
    && apt-get -y autoremove \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# add additional extensions here:
ARG PHP_EXTENSIONS="bcmath curl intl mailparse mbstring opcache pcntl pdo_sqlite pdo_pgsql pgsql readline sockets xml zip"
RUN install-php-extensions ${PHP_EXTENSIONS} @composer

RUN cp $PHP_INI_DIR/php.ini-production $PHP_INI_DIR/php.ini
COPY php.ini $PHP_INI_DIR/conf.d/zz-custom.ini

ARG DOCKER_GID=999
ARG DOCKER_UID=999
RUN groupadd -o -g $DOCKER_GID nonroot \
    && useradd -o -m -s /bin/bash -u $DOCKER_UID -g $DOCKER_GID nonroot

# ------------------------------------------------------
# XDG Base Directories + Composer clean setup
# ------------------------------------------------------
ENV XDG_CONFIG_HOME=/home/nonroot/.config \
    XDG_DATA_HOME=/home/nonroot/.local/share \
    XDG_CACHE_HOME=/home/nonroot/.cache

ENV COMPOSER_HOME=$XDG_DATA_HOME/composer \
    COMPOSER_CACHE_DIR=$XDG_CACHE_HOME/composer \
    PATH="$XDG_DATA_HOME/composer/vendor/bin:$PATH"

RUN mkdir -p $XDG_CONFIG_HOME $XDG_DATA_HOME $XDG_CACHE_HOME && \
    mkdir -p $COMPOSER_HOME/vendor/bin && \
    chown -R nonroot:nonroot /home/nonroot

ENV HOST="0.0.0.0"
WORKDIR /app
USER nonroot

#-----------------------------------------------------------CLI------------------------------------------------------
FROM base AS cli
USER root
# Latest releases available at https://github.com/aptible/supercronic/releases
ENV SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/v0.2.49/supercronic-linux-amd64 \
    SUPERCRONIC_SHA1SUM=e63c11a9726b775a6a11801e81af4f3fb926aa68 \
    SUPERCRONIC=supercronic-linux-amd64

RUN curl -fsSLO "$SUPERCRONIC_URL" \
 && echo "${SUPERCRONIC_SHA1SUM}  ${SUPERCRONIC}" | sha1sum -c - \
 && chmod +x "$SUPERCRONIC" \
 && mv "$SUPERCRONIC" "/usr/local/bin/${SUPERCRONIC}" \
 && ln -s "/usr/local/bin/${SUPERCRONIC}" /usr/local/bin/supercronic

USER nonroot
COPY --chown=nonroot:nonroot crontab /home/nonroot/crontab

# Default: interactive shell, services override it with their own command
CMD ["bash"]

#-----------------------------------------------------------WEB------------------------------------------------------
FROM base AS web
ENV SERVER_NAME=":80"
ENV SERVER_ROOT="/app/public"

COPY --from=caddy-builder /usr/local/bin/frankenphp /usr/local/bin/frankenphp
COPY Caddyfile /etc/caddy/Caddyfile

HEALTHCHECK --interval=30s --timeout=5s --start-period=3s --retries=3 \
    CMD curl --fail http://localhost:2020/health || exit 1

CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]
