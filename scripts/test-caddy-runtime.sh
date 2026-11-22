#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
python3 "${repo_root}/test/features/caddy/test_release_resolution.py"
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

docker run --detach --name "${name}" \
    --health-start-period 8s --health-start-interval 250ms --health-interval 500ms --health-retries 2 \
    --entrypoint /bin/sh "${image}" -ec '
    echo pending.example.test > /etc/caddy/required-hosts.d/sample-pending.host
    printf ":8082 {\n    respond \"ready\"\n}\n" > /etc/caddy/system.d/sample-readiness.caddy
    mkdir -p /etc/services.d/sample-legacy
    printf "#!/bin/sh\ntouch /tmp/sample-legacy-started\nexec sleep infinity\n" > /etc/services.d/sample-legacy/run
    chmod 0755 /etc/services.d/sample-legacy/run
    exec /init /bin/sh -ec "touch /tmp/sample-cmd-started; exec /command/s6-pause"
' >/dev/null

wait_for() {
    for _ in $(seq 1 300); do
        if "$@"; then return 0; fi
        sleep 0.25
    done
    docker inspect --format '{{json .State.Health}}' "${name}" >&2
    docker logs --tail 25 "${name}" >&2
    return 1
}

has_health() {
    test "$(docker inspect --format '{{.State.Health.Status}}' "${name}")" = "$1"
}

# Caddy's DNS wait affects Docker health while legacy services and CMD start.
has_health starting
wait_for docker exec "${name}" test -f /tmp/sample-legacy-started
wait_for docker exec "${name}" test -f /tmp/sample-cmd-started
wait_for has_health unhealthy
docker exec "${name}" rm /etc/caddy/required-hosts.d/sample-pending.host
wait_for has_health healthy
test "$(docker exec "${name}" curl -fsS http://127.0.0.1:8082)" = ready

# A broken config at startup remains unhealthy until a new server loads it.
docker exec "${name}" sh -c 'echo "invalid configuration {" > /etc/caddy/system.d/sample-invalid.caddy'
docker exec "${name}" /command/s6-svc -r /run/service/caddy
wait_for has_health unhealthy
if docker exec "${name}" /run/service/caddy/data/healthcheck; then
    echo 'Caddy answered its readiness probe with an invalid configuration.' >&2
    exit 1
fi
docker exec "${name}" rm /etc/caddy/system.d/sample-invalid.caddy
wait_for has_health healthy
test "$(docker exec "${name}" curl -fsS http://127.0.0.1:8082)" = ready

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

docker exec "${name}" bash -c 'printf "http://127.0.0.1:8081 {\n    bind 127.0.0.1\n    respond \"system\"\n}\n" > /etc/caddy/system.d/system-test.caddy'
for _ in $(seq 1 30); do
    if [ "$(docker exec "${name}" curl -fsS http://127.0.0.1:8081 2>/dev/null || true)" = system ]; then
        break
    fi
    sleep 0.5
done
test "$(docker exec "${name}" curl -fsS http://127.0.0.1:8081)" = system

docker exec "${name}" rm /etc/caddy/system.d/system-test.caddy
for _ in $(seq 1 30); do
    if ! docker exec "${name}" curl -fsS http://127.0.0.1:8081 >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done
if docker exec "${name}" curl -fsS http://127.0.0.1:8081 >/dev/null 2>&1; then
    echo "Deleted system.d fragment remained active." >&2
    exit 1
fi

printf 'Caddy s6 runtime and configuration watcher checks passed.\n'
