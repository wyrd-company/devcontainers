ARG VARIANT="noble"
FROM mcr.microsoft.com/devcontainers/base:${VARIANT}

ARG S6_OVERLAY_VERSION="3.2.3.2"
ARG TARGETARCH

USER root

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) s6_arch="x86_64" ;; \
        arm64) s6_arch="aarch64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    command -v curl; \
    command -v sha256sum; \
    command -v tar; \
    download_dir="$(mktemp -d)"; \
    release_url="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}"; \
    for archive in s6-overlay-noarch.tar.xz "s6-overlay-${s6_arch}.tar.xz"; do \
        curl --fail --location --silent --show-error --output "${download_dir}/${archive}" "${release_url}/${archive}"; \
        curl --fail --location --silent --show-error --output "${download_dir}/${archive}.sha256" "${release_url}/${archive}.sha256"; \
        (cd "${download_dir}" && sha256sum --check "${archive}.sha256"); \
        tar --extract --xz --preserve-permissions --file "${download_dir}/${archive}" --directory /; \
    done; \
    rm -rf "${download_dir}"; \
    test -x /init; \
    test -x /command/s6-svscan; \
    /command/s6-rc --no-lock help >/dev/null

# Limit the vscode user's sudo access to apt installs and s6-overlay service control.
COPY sudoers.d/vscode /etc/sudoers.d/vscode
RUN set -eux; \
    chmod 0440 /etc/sudoers.d/vscode; \
    visudo --check --file=/etc/sudoers.d/vscode; \
    ! sudo -n -l -U vscode /bin/true >/dev/null 2>&1

# One D-Bus session bus for the vscode user, supervised by s6. Without
# DBUS_SESSION_BUS_ADDRESS, D-Bus clients (libsecret, Go keyrings, VS Code)
# autolaunch a new dbus-daemon per call that never exits. dbus-x11, which
# provides dbus-launch, is deliberately not installed.
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends dbus-daemon; \
    ! dpkg -s dbus-x11 >/dev/null 2>&1; \
    rm -rf /var/lib/apt/lists/*
COPY s6-overlay/ /etc/s6-overlay/
RUN set -eux; \
    chmod 0755 /etc/s6-overlay/s6-rc.d/dbus-session/run; \
    command -v dbus-daemon
ENV DBUS_SESSION_BUS_ADDRESS="unix:path=/run/dbus-session/bus"

# bao-secret reads OpenBao secrets with the curl and jq of the upstream image,
# without installing the OpenBao CLI.
COPY --chmod=0755 bao-secret /usr/local/bin/bao-secret
RUN set -eux; \
    command -v curl; \
    command -v jq; \
    bash -n /usr/local/bin/bao-secret

COPY --chmod=0755 check-s6-health /usr/local/bin/check-s6-health
HEALTHCHECK --interval=10s --timeout=3s --start-period=2m --start-interval=1s --retries=3 \
    CMD ["/usr/local/bin/check-s6-health"]

LABEL org.opencontainers.image.authors="Bob Langley" \
      org.opencontainers.image.description="Microsoft Dev Container Ubuntu base with s6-overlay, a D-Bus session bus and an OpenBao secret reader" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/wyrd-company/devcontainers" \
      org.opencontainers.image.title="Ubuntu Dev Container base with s6-overlay"

ENTRYPOINT ["/init"]
CMD ["/command/s6-pause"]
