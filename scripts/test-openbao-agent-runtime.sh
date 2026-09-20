#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
image="${1:-devcontainers-openbao-agent-runtime:test}"
name="openbao-agent-runtime-test-${RANDOM}-$$"

cleanup() {
    docker stop "${name}" >/dev/null 2>&1 || true
    docker rm "${name}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker build \
    --file "${repo_root}/test/features/openbao-agent/runtime.Dockerfile" \
    --tag "${image}" \
    "${repo_root}"

docker run --detach \
    --name "${name}" \
    --env SAMPLE_RUNTIME_VALUE=sample-runtime-value \
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

docker exec --user vscode \
    --env BAO_ADDR=http://127.0.0.1:8200 \
    --env BAO_TOKEN=sample-token \
    "${name}" \
    bao kv put secret/example value=sample-secret >/dev/null

for _ in $(seq 1 60); do
    rendered_secret="$(docker exec "${name}" sh -c 'cat /home/vscode/.openbao-rendered-secret 2>/dev/null || true')"
    if [ "${rendered_secret}" = sample-secret ]; then
        break
    fi
    sleep 0.5
done
test "$(docker exec "${name}" cat /home/vscode/.openbao-rendered-secret)" = sample-secret

agent_pid="$(docker exec "${name}" pgrep --full --exact \
    '/usr/local/bin/bao agent -config=/etc/openbao/agent.hcl' | head -n 1)"
test -n "${agent_pid}"
test "$(docker exec "${name}" ps -o user= -p "${agent_pid}" | tr -d ' ')" = vscode
docker exec --user vscode "${name}" sh -c \
    "tr '\0' '\n' </proc/${agent_pid}/environ | grep -qx SAMPLE_RUNTIME_VALUE=sample-runtime-value"
docker exec "${name}" test -s /home/vscode/.openbao-agent-token

previous_pid="${agent_pid}"
docker exec "${name}" /command/s6-svc -r /run/service/openbao-agent
for _ in $(seq 1 60); do
    agent_pid="$(docker exec "${name}" pgrep --full --exact \
        '/usr/local/bin/bao agent -config=/etc/openbao/agent.hcl' | head -n 1 || true)"
    if [ -n "${agent_pid}" ] && [ "${agent_pid}" != "${previous_pid}" ]; then
        break
    fi
    sleep 0.5
done
test -n "${agent_pid}"
test "${agent_pid}" != "${previous_pid}"
test "$(docker exec "${name}" cat /home/vscode/.openbao-rendered-secret)" = sample-secret

printf 'OpenBao Agent s6 runtime checks passed.\n'
