#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
image="${1:-devcontainers-openbao-secret-files-runtime:test}"
scratch="$(mktemp -d)"
container=""
mount_container=""
collector_command='/usr/local/bin/opentelemetry-collector --config=/etc/opentelemetry-collector/config.yaml'
dagu_command='/usr/local/bin/dagu start-all --host 127.0.0.1 --port 8080'
# shellcheck disable=SC2016
literal_value='$(id) `id` "quoted" '"'"'single'"'"' back\slash #hash key=value'

cleanup() {
    # Only containers this run created, by id.
    for id in "${container}" "${mount_container}"; do
        [ -n "${id}" ] || continue
        docker rm --force "${id}" >/dev/null 2>&1 || true
    done
    rm -rf "${scratch}"
}
trap cleanup EXIT

service_pid() {
    docker exec "${container}" pgrep --full --exact "$1" | head -n 1 || true
}

environ_of() {
    docker exec --user vscode "${container}" sh -c "tr '\\0' '\\n' </proc/$1/environ"
}

wait_for_collector() {
    for _ in $(seq 1 120); do
        if docker exec "${container}" curl --fail --silent http://127.0.0.1:13133/ >/dev/null 2>&1; then
            return
        fi
        sleep 0.5
    done
    docker logs "${container}" >&2 || true
    return 1
}

docker build \
    --file "${repo_root}/test/features/openbao-secret-files/runtime.Dockerfile" \
    --tag "${image}" \
    "${repo_root}"

container="$(docker run --detach \
    --env SAMPLE_PRECEDENCE_VALUE=from-container \
    "${image}")"

docker exec --detach --user vscode \
    --env BAO_DEV_ROOT_TOKEN_ID=sample-token \
    "${container}" \
    bao server -dev -dev-listen-address=127.0.0.1:8200

for _ in $(seq 1 60); do
    if docker exec "${container}" curl --fail --silent http://127.0.0.1:8200/v1/sys/health >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done
docker exec "${container}" curl --fail --silent http://127.0.0.1:8200/v1/sys/health >/dev/null

test "$(docker exec "${container}" stat --format '%U:%G %a' /run/openbao/secrets)" = 'root:openbao-secrets 2750'
docker exec "${container}" id -nG vscode | tr ' ' '\n' | grep -qx openbao-secrets

# The Agent configuration names both consumer files, so both consumers wait.
sleep 3
test -z "$(service_pid "${collector_command}")"
test -z "$(service_pid "${dagu_command}")"
docker logs "${container}" 2>&1 \
    | grep -F '[openbao-wait-for-secrets] Waiting for /run/openbao/secrets/opentelemetry-collector.env' >/dev/null
docker logs "${container}" 2>&1 \
    | grep -F '[openbao-wait-for-secrets] Waiting for /run/openbao/secrets/dagu.env' >/dev/null

# Only a destination assignment declares a file.
for feature in commented-feature slashed-feature mentioned-feature sample-feature; do
    docker exec --user vscode "${container}" timeout 5 /usr/local/bin/openbao-wait-for-secrets "${feature}"
done

docker exec --user vscode \
    --env BAO_ADDR=http://127.0.0.1:8200 \
    --env BAO_TOKEN=sample-token \
    "${container}" \
    bao kv put secret/example \
    username=sample-user token=sample-token precedence=from-secret \
    "literal=${literal_value}" \
    empty= >/dev/null

wait_for_collector
collector_pid="$(service_pid "${collector_command}")"
test -n "${collector_pid}"
test "$(docker exec "${container}" ps -o user= -p "${collector_pid}" | tr -d ' ')" = vscode
environ_of "${collector_pid}" >"${scratch}/collector.env"
grep -Fx 'SAMPLE_HEADER_VALUE=Basic c2FtcGxlLXVzZXI6c2FtcGxlLXRva2Vu' "${scratch}/collector.env" >/dev/null
grep -Fx 'SAMPLE_PRECEDENCE_VALUE=from-container' "${scratch}/collector.env" >/dev/null
grep -Fx "SAMPLE_LITERAL_VALUE=${literal_value}" "${scratch}/collector.env" >/dev/null
grep -Fx 'SAMPLE_EMPTY_VALUE=' "${scratch}/collector.env" >/dev/null

for _ in $(seq 1 60); do
    dagu_pid="$(service_pid "${dagu_command}")"
    [ -z "${dagu_pid}" ] || break
    sleep 0.5
done
test -n "${dagu_pid}"
environ_of "${dagu_pid}" | grep -Fx 'SAMPLE_DAGU_VALUE=from-secret' >/dev/null

# A malformed line stops the launcher instead of exporting a guess.
docker exec "${container}" sh -c 'printf "not a pair\n" >/run/openbao/secrets/opentelemetry-collector.env'
output="$(docker exec --user vscode "${container}" /usr/local/bin/opentelemetry-collector-service 2>&1 || true)"
printf '%s\n' "${output}" | grep -F 'contains a line that is not NAME=value' >/dev/null
# A file the service user cannot read stops the launcher instead of starting without it.
docker exec "${container}" chmod 0600 /run/openbao/secrets/opentelemetry-collector.env
output="$(docker exec --user vscode "${container}" /usr/local/bin/opentelemetry-collector-service 2>&1 || true)"
printf '%s\n' "${output}" | grep -F 'exists but is not readable by vscode' >/dev/null

# The development server does not survive a restart, so a consumer that
# starts here would have read a file from the previous start.
docker restart "${container}" >/dev/null
sleep 5
test -z "$(service_pid "${collector_command}")"
docker exec "${container}" test ! -e /run/openbao/secrets/opentelemetry-collector.env

# The Feature owns /run/openbao/secrets and refuses to clear a mount there.
mkdir -p "${scratch}/mounted"
printf 'keep\n' >"${scratch}/mounted/host-file"
mount_container="$(docker run --detach \
    --mount "type=bind,source=${scratch}/mounted,target=/run/openbao/secrets" \
    "${image}")"
sleep 5
test -f "${scratch}/mounted/host-file"
docker logs "${mount_container}" 2>&1 | grep -F '/run/openbao/secrets is a mount point' >/dev/null
test -z "$(docker exec "${mount_container}" pgrep --full --exact '/usr/local/bin/bao agent -config=/etc/openbao/agent.hcl' | head -n 1 || true)"

printf 'OpenBao secret file runtime checks passed.\n'
