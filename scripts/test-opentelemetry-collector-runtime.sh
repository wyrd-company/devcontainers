#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
image="${1:-devcontainers-opentelemetry-collector-runtime:test}"
name="opentelemetry-collector-runtime-test-${RANDOM}-$$"

cleanup() {
    docker stop "${name}" >/dev/null 2>&1 || true
    docker rm "${name}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker build \
    --file "${repo_root}/test/features/opentelemetry-collector/runtime.Dockerfile" \
    --tag "${image}" \
    "${repo_root}"

docker run --detach \
    --name "${name}" \
    --env SAMPLE_RUNTIME_VALUE=sample-runtime-value \
    "${image}" >/dev/null

for _ in $(seq 1 60); do
    if docker exec "${name}" curl --fail --silent http://127.0.0.1:13133/ >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done
docker exec "${name}" curl --fail --silent http://127.0.0.1:13133/ >/dev/null

collector_pid="$(docker exec "${name}" pgrep --full --exact \
    '/usr/local/bin/opentelemetry-collector --config=/etc/opentelemetry-collector/config.yaml' \
    | head -n 1)"
test -n "${collector_pid}"
test "$(docker exec "${name}" ps -o user= -p "${collector_pid}" | tr -d ' ')" = vscode
docker exec --user vscode "${name}" sh -c \
    "tr '\0' '\n' </proc/${collector_pid}/environ | grep -qx SAMPLE_RUNTIME_VALUE=sample-runtime-value"

docker exec "${name}" curl --fail --silent \
    --header 'Content-Type: application/json' \
    --data '{"resourceLogs":[]}' \
    http://127.0.0.1:4318/v1/logs >/dev/null

previous_pid="${collector_pid}"
docker exec "${name}" /command/s6-svc -r /run/service/opentelemetry-collector
for _ in $(seq 1 60); do
    collector_pid="$(docker exec "${name}" pgrep --full --exact \
        '/usr/local/bin/opentelemetry-collector --config=/etc/opentelemetry-collector/config.yaml' \
        | head -n 1 || true)"
    if [ -n "${collector_pid}" ] && [ "${collector_pid}" != "${previous_pid}" ] \
        && docker exec "${name}" curl --fail --silent http://127.0.0.1:13133/ >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done
test -n "${collector_pid}"
test "${collector_pid}" != "${previous_pid}"
docker exec "${name}" curl --fail --silent http://127.0.0.1:13133/ >/dev/null

printf 'OpenTelemetry Collector s6 runtime checks passed.\n'
