ARG BASE_IMAGE=ghcr.io/wyrd-company/devcontainers/base:noble
FROM ${BASE_IMAGE}

COPY src/features/openbao-agent /tmp/openbao-agent-feature
COPY src/features/opentelemetry-collector /tmp/opentelemetry-collector-feature
COPY src/features/dagu /tmp/dagu-feature

# The Agent runs as root by default and the consumers as vscode, so the
# openbao-secrets group carries the read access.
RUN VERSION=latest \
    CONFIGPATH=/etc/openbao/agent.d \
    _REMOTE_USER=vscode \
    /tmp/openbao-agent-feature/install.sh \
    && VERSION=latest \
    DISTRIBUTION=core \
    SERVICEUSER=automatic \
    _REMOTE_USER=vscode \
    /tmp/opentelemetry-collector-feature/install.sh \
    && VERSION=latest \
    HOST=127.0.0.1 \
    PORT=8080 \
    SERVICEUSER=automatic \
    DNSNAME= \
    _REMOTE_USER=vscode \
    /tmp/dagu-feature/install.sh \
    && rm -rf /tmp/openbao-agent-feature /tmp/opentelemetry-collector-feature /tmp/dagu-feature

RUN install -d -m 0755 /etc/openbao/agent.d
COPY --chmod=0644 test/features/openbao-secret-files/runtime-agent.hcl /etc/openbao/agent.d/agent.hcl
COPY --chmod=0644 test/features/openbao-secret-files/runtime-agent.json /etc/openbao/agent.d/agent.json
COPY --chmod=0600 test/features/openbao-agent/runtime-token /root/.openbao-token
