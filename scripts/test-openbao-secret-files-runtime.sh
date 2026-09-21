#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
image="${1:-devcontainers-openbao-secret-files-runtime:test}"
name="openbao-secret-files-runtime-test-${RANDOM}-$$"
collector_command='/usr/local/bin/opentelemetry-collector --config=/etc/opentelemetry-collector/config.yaml'

cleanup() {
    docker stop "${name}" >/dev/null 2>&1 || true
    docker rm "${name}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

collector_pid() {
    docker exec "${name}" pgrep --full --exact "${collector_command}" | head -n 1 || true
}

wait_for_collector() {
    for _ in $(seq 1 120); do
        if docker exec "${name}" curl --fail --silent http://127.0.0.1:13133/ >/dev/null 2>&1; then
            return
        fi
        sleep 0.5
    done
    docker logs "${name}" >&2 || true
    return 1
}

docker build \
    --file "${repo_root}/test/features/openbao-secret-files/runtime.Dockerfile" \
    --tag "${image}" \
    "${repo_root}"

docker run --detach \
    --name "${name}" \
    --env SAMPLE_PRECEDENCE_VALUE=from-container \
    "${image}" >/dev/null

docker exec --detach --user vscode \
    --env BAO_DEV_ROOT_TOKEN_ID=sample-token \
    "${name}" \
    bao server -dev -dev-listen-address=127.0.0.1:8200

for _ in $(seq 1 60); do
    if docker exec "${name}" curl --fail --silent http://127.0.0.1:8200/v1/sys/health >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done
docker exec "${name}" curl --fail --silent http://127.0.0.1:8200/v1/sys/health >/dev/null

test "$(docker exec "${name}" stat --format '%U:%G %a' /run/openbao/secrets)" = 'root:openbao-secrets 2750'
docker exec "${name}" id -nG vscode | tr ' ' '\n' | grep -qx openbao-secrets

# The Agent configuration names the Collector file, so the Collector waits for it.
sleep 3
test -z "$(collector_pid)"
docker logs "${name}" 2>&1 \
    | grep -Fq '[openbao-wait-for-secrets] Waiting for a readable /run/openbao/secrets/opentelemetry-collector.env'

# A destination that appears only in a comment is not a declaration.
docker exec --user vscode "${name}" timeout 5 /usr/local/bin/openbao-wait-for-secrets dagu
# A Feature without a template does not wait.
docker exec --user vscode "${name}" timeout 5 /usr/local/bin/openbao-wait-for-secrets sample-feature

docker exec --user vscode \
    --env BAO_ADDR=http://127.0.0.1:8200 \
    --env BAO_TOKEN=sample-token \
    "${name}" \
    bao kv put secret/example username=sample-user token=sample-token precedence=from-secret >/dev/null

wait_for_collector
pid="$(collector_pid)"
test -n "${pid}"
test "$(docker exec "${name}" ps -o user= -p "${pid}" | tr -d ' ')" = vscode
docker exec --user vscode "${name}" sh -c \
    "tr '\0' '\n' </proc/${pid}/environ | grep -qx 'SAMPLE_HEADER_VALUE=Basic c2FtcGxlLXVzZXI6c2FtcGxlLXRva2Vu'"
docker exec --user vscode "${name}" sh -c \
    "tr '\0' '\n' </proc/${pid}/environ | grep -qx SAMPLE_PRECEDENCE_VALUE=from-container"

# The development server does not survive a restart, so a Collector that
# starts here would have read the file from the previous start.
docker restart "${name}" >/dev/null
sleep 5
test -z "$(collector_pid)"
docker exec "${name}" test ! -e /run/openbao/secrets/opentelemetry-collector.env

printf 'OpenBao secret file runtime checks passed.\n'
