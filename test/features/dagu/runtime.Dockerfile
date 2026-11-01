ARG BASE_IMAGE=ghcr.io/wyrd-company/devcontainers/base:noble
FROM ${BASE_IMAGE}

COPY src/features/dagu /tmp/dagu-feature

RUN VERSION=latest \
    HOST=127.0.0.1 \
    PORT=8080 \
    CONFIGPATH="/etc/sample dagu/config.yaml" \
    SERVICEUSER=automatic \
    DNSNAME= \
    _REMOTE_USER=vscode \
    /tmp/dagu-feature/install.sh \
    && rm -rf /tmp/dagu-feature

# The base path proves that the service loads this file. CLI host/port must win.
RUN mkdir -p '/etc/sample dagu' \
    && printf 'host: 192.0.2.10\nport: 9999\nbase_path: /sample-config\n' >'/etc/sample dagu/config.yaml' \
    && chmod 0644 '/etc/sample dagu/config.yaml'
