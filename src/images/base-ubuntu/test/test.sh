#!/usr/bin/env bash

set -euo pipefail

image="${1:?usage: test.sh IMAGE}"
test_image="${image}-s6-test"
container="base-ubuntu-s6-test-${RANDOM}"

docker build --build-arg "IMAGE=${image}" --tag "${test_image}" "$(dirname "$0")"
"$(dirname "$0")/../../../../scripts/check-sudo-no-all.sh" "${test_image}"

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

# One D-Bus session bus runs as vscode, at the address every process inherits.
bus_socket=/run/dbus-session/bus
get_bus_id=(dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.GetId)
for _ in $(seq 1 10); do
    docker exec "${container}" test -S "${bus_socket}" && break
    sleep 1
done
test "$(docker exec "${container}" printenv DBUS_SESSION_BUS_ADDRESS)" = "unix:path=${bus_socket}"
test "$(docker exec "${container}" pgrep -c -x dbus-daemon)" -eq 1
bus_pid="$(docker exec "${container}" pgrep -x dbus-daemon)"
test "$(docker exec "${container}" ps -o user= -p "${bus_pid}")" = vscode
environ_file="$(mktemp)"
docker exec --user vscode "${container}" sh -c "tr '\0' '\n' </proc/${bus_pid}/environ" >"${environ_file}"
grep -qx 'HOME=/home/vscode' "${environ_file}"
grep -qx 'USER=vscode' "${environ_file}"
rm -f "${environ_file}"
docker exec --user vscode "${container}" "${get_bus_id[@]}" >/dev/null
if docker exec "${container}" sh -c 'command -v dbus-launch' >/dev/null; then
    echo "expected no dbus-launch in the image" >&2
    exit 1
fi

# With the address set, clients never autolaunch a daemon of their own. A
# recording dbus-launch proves the check sees an autolaunch when one happens.
docker exec "${container}" sh -c 'printf "%s\n" "#!/bin/sh" "echo \"\$*\" >>/tmp/dbus-launch-calls" "exit 1" >/usr/local/bin/dbus-launch && chmod 0755 /usr/local/bin/dbus-launch'
for _ in 1 2 3; do
    docker exec --user vscode --env DISPLAY=:99 "${container}" "${get_bus_id[@]}" >/dev/null
done
if docker exec "${container}" test -e /tmp/dbus-launch-calls; then
    echo "expected no dbus-launch call while DBUS_SESSION_BUS_ADDRESS is set" >&2
    exit 1
fi
docker exec --user vscode --env DISPLAY=:99 "${container}" \
    env -u DBUS_SESSION_BUS_ADDRESS "${get_bus_id[@]}" >/dev/null 2>&1 || true
docker exec "${container}" grep -q -- --autolaunch /tmp/dbus-launch-calls
docker exec "${container}" rm -f /usr/local/bin/dbus-launch /tmp/dbus-launch-calls
test "$(docker exec "${container}" pgrep -c -x dbus-daemon)" -eq 1

# A restart replaces the daemon and the bus answers again on the same socket.
docker exec --user vscode "${container}" sudo -n /command/s6-svc -r /run/service/dbus-session
for _ in $(seq 1 10); do
    new_bus_pid="$(docker exec "${container}" pgrep -x dbus-daemon || true)"
    [ -n "${new_bus_pid}" ] && [ "${new_bus_pid}" != "${bus_pid}" ] && break
    sleep 1
done
test "${new_bus_pid}" != "${bus_pid}"
for _ in $(seq 1 10); do
    docker exec --user vscode "${container}" "${get_bus_id[@]}" >/dev/null 2>&1 && break
    sleep 1
done
docker exec --user vscode "${container}" "${get_bus_id[@]}" >/dev/null

# The vscode user may only use sudo for apt installs and s6-overlay service control.
allowed=(
    "apt-get update"
    "apt-get -qq update"
    "apt-get install -y --no-install-recommends curl"
    "apt-get -y install curl"
    "apt update"
    "apt install -y curl"
    "apt-get update -qq"
    "apt-get install -y curl=1.0-1"
    "apt-get -o Dpkg::Options::=--force-confnew install -y curl"
    "apt-get -t sample-release install curl"
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
    "apt-get remove curl install bash"
    "apt-get purge curl update bash"
    "apt-get --target-release install remove curl"
    "apt-get -t install remove curl"
    "apt-get install curl-"
    "apt-get install curl_"
    "apt-get update remove curl"
    "apt-get upgrade"
    "apt-get autoremove"
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
