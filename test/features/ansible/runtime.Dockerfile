ARG BASE_IMAGE=ghcr.io/wyrd-company/devcontainers/base:noble
FROM ${BASE_IMAGE}

ARG SOURCE=
ARG SERVICEUSER=root
ARG REQUIREMENTS=
ARG ARGS=

COPY src/features/ansible /tmp/ansible-feature

RUN SOURCE="${SOURCE}" \
    PLAYBOOK=site.yml \
    REF= \
    INVENTORY= \
    REQUIREMENTS="${REQUIREMENTS}" \
    ARGS="${ARGS}" \
    CHECKOUTDIR=/var/lib/ansible-setup/checkout \
    SERVICEUSER="${SERVICEUSER}" \
    _REMOTE_USER=vscode \
    /tmp/ansible-feature/install.sh \
    && rm -rf /tmp/ansible-feature

# A service that follows the repository convention: it depends on ansible-setup
# because Ansible is present.
RUN service_dir=/etc/s6-overlay/s6-rc.d/sample-dependent \
    && install -d "${service_dir}/dependencies.d" \
    && printf 'longrun\n' >"${service_dir}/type" \
    && touch "${service_dir}/dependencies.d/base" "${service_dir}/dependencies.d/ansible-setup" \
    && printf '#!/command/with-contenv bash\ntouch /var/tmp/sample-dependent-started\nexec sleep infinity\n' >"${service_dir}/run" \
    && chmod 0755 "${service_dir}/run" \
    && touch /etc/s6-overlay/user-bundles.d/user/contents.d/sample-dependent
