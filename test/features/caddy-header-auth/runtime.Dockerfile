ARG BASE_IMAGE=ghcr.io/wyrd-company/devcontainers/base:noble
FROM ${BASE_IMAGE}

COPY src/features/caddy /tmp/caddy-feature
COPY src/features/caddy-header-auth /tmp/caddy-header-auth-feature

RUN VERSION=latest \
    ACMECA= \
    ACMECAROOT= \
    CONFIGUSER=automatic \
    _REMOTE_USER=vscode \
    /tmp/caddy-feature/install.sh \
    && rm -rf /tmp/caddy-feature

RUN SERVICEUSER=automatic \
    SOCKETGROUP=automatic \
    SOCKETPATH=/run/caddy-header-auth/auth.sock \
    CONFIGDIR=/etc/caddy-header-auth/conf.d \
    TIMEOUTSECONDS=10 \
    _REMOTE_USER=vscode \
    /tmp/caddy-header-auth-feature/install.sh \
    && rm -rf /tmp/caddy-header-auth-feature
