# Installs one Feature on the base image, optionally beside a stand-in for the
# Ansible Feature's `ansible-setup` oneshot. The stand-in lets the dependency
# edge be tested without the Ansible Feature.
ARG BASE_IMAGE=ghcr.io/wyrd-company/devcontainers/base:noble
FROM node:24-bookworm-slim AS node

FROM ${BASE_IMAGE}
# Node.js is a prerequisite of the npm-based Features.
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm

ARG FIXTURE=absent
COPY test/ansible-dependency/ansible-setup-fixture.sh /tmp/ansible-setup-fixture.sh
RUN if [ "${FIXTURE}" = present ]; then sh /tmp/ansible-setup-fixture.sh; fi \
    && rm -f /tmp/ansible-setup-fixture.sh

ARG FEATURE
ARG FEATURE_ENV=
COPY src/features/${FEATURE} /tmp/feature
# shellcheck disable=SC2086
RUN env ${FEATURE_ENV} _REMOTE_USER=vscode /tmp/feature/install.sh \
    && rm -rf /tmp/feature
