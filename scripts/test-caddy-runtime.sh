#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
base_image="${BASE_IMAGE:-$("${repo_root}/scripts/build-base-image.sh" noble)}"
image="${1:-devcontainers-caddy-runtime:test}"
name="caddy-runtime-test-${RANDOM}-$$"

cleanup() {
    docker stop "${name}" >/dev/null 2>&1 || true
    docker rm "${name}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker build \
    --file "${repo_root}/test/features/caddy/runtime.Dockerfile" \
    --build-arg "BASE_IMAGE=${base_image}" \
    --tag "${image}" \
    "${repo_root}"

"${repo_root}/scripts/check-sudo-no-all.sh" "${image}"

docker run --detach --name "${name}" "${image}" >/dev/null

for _ in $(seq 1 30); do
    if docker exec "${name}" test -S /run/caddy/admin.sock; then
        break
    fi
    sleep 0.5
done
docker exec "${name}" test -S /run/caddy/admin.sock

docker exec "${name}" runuser --user vscode -- \
    bash -c "printf ':8080 {\n    respond \"first\"\n}\n' > /etc/caddy/conf.d/test.caddy"
for _ in $(seq 1 30); do
    if [ "$(docker exec "${name}" curl -fsS http://127.0.0.1:8080 2>/dev/null || true)" = first ]; then
        break
    fi
    sleep 0.5
done
test "$(docker exec "${name}" curl -fsS http://127.0.0.1:8080)" = first

docker exec "${name}" runuser --user vscode -- \
    bash -c "printf ':8080 {\n    respond \"second\"\n}\n' > /etc/caddy/conf.d/test.caddy"
for _ in $(seq 1 30); do
    if [ "$(docker exec "${name}" curl -fsS http://127.0.0.1:8080 2>/dev/null || true)" = second ]; then
        break
    fi
    sleep 0.5
done
test "$(docker exec "${name}" curl -fsS http://127.0.0.1:8080)" = second

docker exec "${name}" runuser --user vscode -- \
    bash -c "printf 'this is not valid caddy configuration {\n' > /etc/caddy/conf.d/test.caddy"
sleep 2
test "$(docker exec "${name}" curl -fsS http://127.0.0.1:8080)" = second

docker exec "${name}" rm /etc/caddy/conf.d/test.caddy
for _ in $(seq 1 30); do
    if ! docker exec "${name}" curl -fsS http://127.0.0.1:8080 >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done
if docker exec "${name}" curl -fsS http://127.0.0.1:8080 >/dev/null 2>&1; then
    echo "Deleted fragment remained active." >&2
    exit 1
fi

printf 'Caddy s6 runtime and configuration watcher checks passed.\n'
