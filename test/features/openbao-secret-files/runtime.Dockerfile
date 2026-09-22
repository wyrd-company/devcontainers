ARG BASE_IMAGE=ghcr.io/wyrd-company/devcontainers/base:noble
FROM ${BASE_IMAGE}

COPY src/features/openbao-agent /tmp/openbao-agent-feature
COPY src/features/opentelemetry-collector /tmp/opentelemetry-collector-feature

# The Agent runs as root by default and the Collector as vscode, so the
# openbao-secrets group carries the read access.
RUN VERSION=latest \
    CONFIGPATH=/etc/openbao/agent.hcl \
    _REMOTE_USER=vscode \
    /tmp/openbao-agent-feature/install.sh \
    && VERSION=latest \
    DISTRIBUTION=core \
    SERVICEUSER=automatic \
    _REMOTE_USER=vscode \
    /tmp/opentelemetry-collector-feature/install.sh \
    && rm -rf /tmp/openbao-agent-feature /tmp/opentelemetry-collector-feature

COPY --chmod=0644 test/features/openbao-secret-files/runtime-agent.hcl /etc/openbao/agent.hcl
COPY --chmod=0600 test/features/openbao-agent/runtime-token /root/.openbao-token
