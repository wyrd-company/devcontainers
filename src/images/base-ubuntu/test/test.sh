#!/usr/bin/env bash

set -euo pipefail

image="${1:?usage: test.sh IMAGE}"
test_image="${image}-s6-test"
container="base-ubuntu-s6-test-${RANDOM}"

docker build --build-arg "IMAGE=${image}" --tag "${test_image}" "$(dirname "$0")"

cleanup() {
    docker container rm --force "${container}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run --detach --name "${container}" "${test_image}" \
    >/dev/null

for _ in $(seq 1 30); do
    restart_count="$(docker exec "${container}" sh -c 'test -f /tmp/restart-probe-pids && wc -l </tmp/restart-probe-pids || true')"
    if [ "${restart_count:-0}" -ge 2 ]; then
        break
    fi
    sleep 1
done

docker exec "${container}" sh -c "tr '\0' ' ' </proc/1/cmdline | grep -q s6-svscan"
docker exec "${container}" sh -c 'tr "\0" " " </proc/$(pgrep -x s6-pause)/cmdline | grep -q s6-pause'
docker exec "${container}" sh -c 'test "$(wc -l </tmp/restart-probe-pids)" -ge 2'

# The vscode user may only use sudo for apt installs and s6-overlay service control.
allowed=(
    "apt-get update"
    "apt-get -qq update"
    "apt-get install -y --no-install-recommends curl"
    "apt-get -y install curl"
    "apt update"
    "apt install -y curl"
    "/command/s6-svc -r /run/service/restart-probe"
    "/command/s6-svc -d /run/service/restart-probe"
    "/command/s6-svstat /run/service/restart-probe"
    "/command/s6-rc -u change restart-probe"
)
denied=(
    "true"
    "sh"
    "bash -c id"
    "apt-get remove curl"
    "apt-get purge curl"
    "apt remove curl"
    "dpkg -i package.deb"
    "/command/s6-svc -r /etc/passwd"
    "/command/s6-svscanctl -t /run/service"
    "chmod 4755 /bin/sh"
    "passwd root"
)
for command in "${allowed[@]}"; do
    docker exec --user vscode "${container}" sh -c "sudo -n -l ${command} >/dev/null" \
        || { echo "expected sudo to allow: ${command}" >&2; exit 1; }
done
for command in "${denied[@]}"; do
    if docker exec --user vscode "${container}" sh -c "sudo -n -l ${command} >/dev/null 2>&1"; then
        echo "expected sudo to deny: ${command}" >&2
        exit 1
    fi
done
docker exec --user vscode "${container}" sh -c 'sudo -n DEBIAN_FRONTEND=noninteractive apt-get -s install curl >/dev/null'
before="$(docker exec "${container}" sh -c 'wc -l </tmp/restart-probe-pids')"
docker exec --user vscode "${container}" sudo -n /command/s6-svc -r /run/service/restart-probe
for _ in $(seq 1 10); do
    after="$(docker exec "${container}" sh -c 'wc -l </tmp/restart-probe-pids')"
    [ "${after}" -gt "${before}" ] && break
    sleep 1
done
test "${after}" -gt "${before}"

docker stop --time 10 "${container}" >/dev/null
test "$(docker inspect --format '{{.State.ExitCode}}' "${container}")" -eq 0
