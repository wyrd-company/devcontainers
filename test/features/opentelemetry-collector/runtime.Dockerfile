ARG BASE_IMAGE=ghcr.io/wyrd-company/devcontainers/base:noble
FROM ${BASE_IMAGE}

COPY src/features/opentelemetry-collector /tmp/opentelemetry-collector-feature

RUN VERSION=latest \
    DISTRIBUTION=core \
    SERVICEUSER=automatic \
    _REMOTE_USER=vscode \
    /tmp/opentelemetry-collector-feature/install.sh \
    && rm -rf /tmp/opentelemetry-collector-feature
