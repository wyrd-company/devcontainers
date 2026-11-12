ARG BASE_IMAGE=ghcr.io/wyrd-company/devcontainers/base:noble
FROM ${BASE_IMAGE}

ARG SERVICE_USER=automatic
ARG WATCH_CONFIG_METHOD=recommended
ARG WATCH_CONFIG_POLL_INTERVAL_SECONDS=30

COPY src/features/vector /tmp/vector-feature

RUN VERSION=latest \
    SERVICEUSER="${SERVICE_USER}" \
    APIADDRESS=localhost:8686 \
    WATCHCONFIGMETHOD="${WATCH_CONFIG_METHOD}" \
    WATCHCONFIGPOLLINTERVALSECONDS="${WATCH_CONFIG_POLL_INTERVAL_SECONDS}" \
    _REMOTE_USER=vscode \
    /tmp/vector-feature/install.sh \
    && rm -rf /tmp/vector-feature
