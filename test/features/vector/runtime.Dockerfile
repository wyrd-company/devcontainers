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

# Changes vscode's UID and GID the way the Dev Container CLI does when the host
# user's IDs differ (updateUID.Dockerfile): it edits passwd and group and fixes
# the ownership of the home directory only. The pipeline directory also gets a
# file another user owns, and the data directory is left with UID 1002, as a
# volume kept from an earlier container would be.
ARG REMAP_UID=
RUN if [ -n "${REMAP_UID}" ]; then \
        sed -i -e "s/^\(vscode:[^:]*:\)[^:]*:[^:]*/\1${REMAP_UID}:${REMAP_UID}/" /etc/passwd \
        && sed -i -e "s/^\(vscode:[^:]*:\)[^:]*:/\1${REMAP_UID}:/" /etc/group \
        && chown -R "${REMAP_UID}:${REMAP_UID}" /home/vscode \
        && install -m 0644 /dev/null /etc/vector/conf.d/sample-install-owned.txt \
        && chown 1000:1000 /etc/vector/conf.d/sample-install-owned.txt \
        && install -m 0644 -o root -g root /dev/null /etc/vector/conf.d/sample-root-owned.txt \
        && install -d -m 0750 /var/lib/vector/sample-previous-container \
        && chown -R 1002:1002 /var/lib/vector; \
    fi
