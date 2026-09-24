#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
image="${1:-devcontainers-dagu-runtime:test}"
name="dagu-runtime-test-${RANDOM}-$$"

cleanup() {
    docker stop "${name}" >/dev/null 2>&1 || true
    docker rm "${name}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker build \
    --file "${repo_root}/test/features/dagu/runtime.Dockerfile" \
    --tag "${image}" \
    "${repo_root}"

"${repo_root}/scripts/check-sudo-no-all.sh" "${image}"

docker run --detach \
    --name "${name}" \
    --env DAGU_HOST=0.0.0.0 \
    --env DAGU_PORT=8123 \
    --env SAMPLE_RUNTIME_VALUE=sample-runtime-value \
    "${image}" >/dev/null

for _ in $(seq 1 60); do
    if docker exec "${name}" curl --fail --silent http://127.0.0.1:8080/ >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done
docker exec "${name}" curl --fail --silent http://127.0.0.1:8080/ >/dev/null

dagu_pid="$(docker exec "${name}" pgrep --exact dagu | head -n 1)"
test -n "${dagu_pid}"
test "$(docker exec "${name}" ps -o user= -p "${dagu_pid}" | tr -d ' ')" = vscode
docker exec --user vscode "${name}" sh -c \
    "tr '\0' '\n' </proc/${dagu_pid}/environ | grep -qx SAMPLE_RUNTIME_VALUE=sample-runtime-value"

if docker exec "${name}" curl --fail --silent http://127.0.0.1:8123/ >/dev/null 2>&1; then
    echo "DAGU_PORT overrode the configured command-line port." >&2
    exit 1
fi

assert_install_rejected() {
    local description="$1"
    local expected="$2"
    shift 2
    local output

    if output="$(docker run --rm \
        --entrypoint /bin/bash \
        --volume "${repo_root}/src/features/dagu:/feature:ro" \
        --volume "${repo_root}/test/features/dagu/failing-checksum-bin:/test-bin:ro" \
        "${image}" \
        -c 'env "$@" /feature/install.sh' bash "$@" 2>&1)"; then
        echo "Invalid configuration was accepted: ${description}." >&2
        exit 1
    fi
    if ! printf '%s\n' "${output}" | grep -Fq "${expected}"; then
        echo "Configuration was rejected for the wrong reason: ${description}." >&2
        printf '%s\n' "${output}" >&2
        exit 1
    fi
}

common_options=(
    VERSION=latest
    HOST=127.0.0.1
    PORT=8080
    SERVICEUSER=automatic
    DNSNAME=
    _REMOTE_USER=vscode
)
assert_install_rejected \
    "out-of-range port" \
    "port must be an integer between 1 and 65535" \
    "${common_options[@]/PORT=8080/PORT=0}"
assert_install_rejected \
    "Caddy registration on a non-loopback host" \
    "dnsName requires host" \
    VERSION=latest HOST=192.0.2.10 PORT=8080 SERVICEUSER=automatic \
    DNSNAME=workflow.test-container.example.test _REMOTE_USER=vscode
assert_install_rejected \
    "Caddy registration without Caddy" \
    "dnsName requires the Caddy Feature" \
    VERSION=latest HOST=127.0.0.1 PORT=8080 SERVICEUSER=automatic \
    DNSNAME=workflow.test-container.example.test _REMOTE_USER=vscode
assert_install_rejected \
    "release archive with a failed checksum" \
    "Checksum verification failed" \
    VERSION=latest HOST=127.0.0.1 PORT=8080 SERVICEUSER=automatic DNSNAME= \
    _REMOTE_USER=vscode PATH=/test-bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

printf 'Dagu s6 runtime checks passed.\n'
