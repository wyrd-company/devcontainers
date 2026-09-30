ARG BASE_IMAGE=ghcr.io/wyrd-company/devcontainers/base:noble
FROM node:24-bookworm-slim AS node
FROM ${BASE_IMAGE} AS codex-tools
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm
RUN npm install --prefix /opt/codex-probe ws
COPY test/features/codex-cli/arguments.test.cjs /opt/codex-probe/arguments.test.cjs
COPY test/features/codex-cli/exec-probe.mjs /opt/codex-probe/exec-probe.mjs
RUN mkdir -p /run/sample-secrets \
    && printf '%s' sample-capability-token-for-integration >'/run/sample-secrets/exec token' \
    && printf '%s' sample-shared-secret-for-integration-tests >'/run/sample-secrets/exec key'
FROM codex-tools
ARG EXECSERVER=false
COPY src/features/codex-cli /tmp/codex-feature
RUN VERSION=latest SERVICEUSER=automatic _REMOTE_USER=vscode EXECSERVER="${EXECSERVER}" /tmp/codex-feature/install.sh \
    && rm -rf /tmp/codex-feature
