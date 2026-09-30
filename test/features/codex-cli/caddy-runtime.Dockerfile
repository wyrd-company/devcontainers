# ---
# relationships:
#   verifies: codex-cli
# ---
ARG NATIVE_IMAGE=devcontainers-codex-runtime:test
FROM ${NATIVE_IMAGE}
COPY src/features/caddy /tmp/caddy-feature
RUN VERSION=latest ACMECA= ACMECAROOT= CONFIGUSER=automatic _REMOTE_USER=vscode /tmp/caddy-feature/install.sh \
    && rm -rf /tmp/caddy-feature
ARG EXECSERVER=true
ARG STARTAPPSERVER=true
COPY src/features/codex-cli /tmp/codex-feature
RUN VERSION=latest SERVICEUSER=automatic _REMOTE_USER=vscode EXECSERVER="${EXECSERVER}" STARTAPPSERVER="${STARTAPPSERVER}" \
    DNSNAME=sample-codex.example.test /tmp/codex-feature/install.sh \
    && rm -rf /tmp/codex-feature \
    && sed -i '/sample-codex.example.test {/a\    tls internal' /etc/caddy/conf.d/codex-cli.caddy \
    && caddy adapt --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null
