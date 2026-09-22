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
    test -x /command/s6-svscan

# Limit the vscode user's sudo access to apt installs and s6-overlay service control.
COPY sudoers.d/vscode /etc/sudoers.d/vscode
RUN set -eux; \
    chmod 0440 /etc/sudoers.d/vscode; \
    visudo --check --file=/etc/sudoers.d/vscode; \
    ! sudo -n -l -U vscode /bin/true >/dev/null 2>&1

LABEL org.opencontainers.image.authors="Bob Langley" \
      org.opencontainers.image.description="Microsoft Dev Container Ubuntu base with s6-overlay" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/wyrd-company/devcontainers" \
      org.opencontainers.image.title="Ubuntu Dev Container base with s6-overlay"

ENTRYPOINT ["/init"]
CMD ["/command/s6-pause"]
