ARG BASE_IMAGE=ghcr.io/wyrd-company/devcontainers/base:noble
FROM ${BASE_IMAGE}

COPY src/features/openbao-agent /tmp/openbao-agent-feature

RUN VERSION=latest \
    SERVICEUSER=vscode \
    CONFIGPATH=/etc/openbao/agent.hcl \
    _REMOTE_USER=vscode \
    /tmp/openbao-agent-feature/install.sh \
    && rm -rf /tmp/openbao-agent-feature

COPY --chmod=0644 test/features/openbao-agent/runtime-agent.hcl /etc/openbao/agent.hcl
COPY --chown=vscode:vscode --chmod=0600 test/features/openbao-agent/runtime-token /home/vscode/.openbao-token
