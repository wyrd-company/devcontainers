ARG BASE_IMAGE=ghcr.io/wyrd-company/devcontainers/base:noble
FROM node:24-bookworm-slim AS node
FROM ${BASE_IMAGE}
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm
RUN npm install --prefix /opt/codex-probe ws
COPY src/features/codex-cli /tmp/codex-feature
RUN VERSION=latest SERVICEUSER=automatic _REMOTE_USER=vscode /tmp/codex-feature/install.sh \
    && rm -rf /tmp/codex-feature
