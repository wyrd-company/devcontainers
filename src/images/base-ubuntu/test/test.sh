#!/usr/bin/env bash

set -euo pipefail

image="${1:?usage: test.sh IMAGE}"
test_image="${image}-s6-test"
container="base-ubuntu-s6-test-${RANDOM}"

docker build --build-arg "IMAGE=${image}" --tag "${test_image}" "$(dirname "$0")"
"$(dirname "$0")/../../../../scripts/check-sudo-no-all.sh" "${test_image}"
health_settings="$(docker image inspect --format \
    '{{.Config.Healthcheck.StartPeriod}} {{.Config.Healthcheck.StartInterval}} {{.Config.Healthcheck.Interval}} {{.Config.Healthcheck.Timeout}} {{.Config.Healthcheck.Retries}}' \
    "${test_image}")"
test "${health_settings}" = '2m0s 1s 10s 3s 3'

cleanup() {
    docker container rm --force "${container}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run --detach --name "${container}" \
    --health-start-period 8s --health-start-interval 250ms --health-interval 500ms --health-retries 2 \
    "${test_image}" >/dev/null

wait_for() {
    for _ in $(seq 1 300); do
        if "$@"; then return 0; fi
        sleep 0.25
    done
    docker inspect --format '{{json .State.Health}}' "${container}" >&2
    docker logs --tail 25 "${container}" >&2
    return 1
}

has_health() {
    test "$(docker inspect --format '{{.State.Health.Status}}' "${container}")" = "$1"
}

expect_probe_failure() {
    local output
    if output="$(docker exec "${container}" /usr/local/bin/check-s6-health 2>&1)" || [ "$output" != "$1" ]; then
        printf 'expected health probe failure "%s", got "%s"\n' "$1" "$output" >&2
        return 1
    fi
}

has_health starting

# Release the longrun first so the oneshot is the only remaining startup gate.
wait_for docker exec "${container}" test -f /tmp/setup-probe-started
wait_for docker exec "${container}" test -f /tmp/ready-probe-started
docker exec "${container}" touch /tmp/ready-probe-release
docker exec "${container}" /command/s6-svwait -U -t 10000 /run/service/ready-probe
expect_probe_failure 's6-rc service has not started: setup-probe'
wait_for has_health unhealthy
docker exec "${container}" touch /tmp/setup-probe-release
wait_for has_health healthy
test "$(docker exec "${container}" /command/s6-svstat -o up,normallyup /run/service/legacy-manual)" = 'false false'

# Probing repeatedly must leave the live lock available for service changes.
docker exec "${container}" sh -ec '
    (
        for attempt in $(seq 1 100); do /usr/local/bin/check-s6-health; done
    ) &
    probe_pid=$!
    for attempt in $(seq 1 100); do /command/s6-rc -u change setup-probe; done
    wait "$probe_pid"
'

# A running service that has not sent its readiness signal still fails.
docker exec "${container}" rm /tmp/ready-probe-started /tmp/ready-probe-release
docker exec "${container}" /command/s6-svc -r /run/service/ready-probe
wait_for docker exec "${container}" test -f /tmp/ready-probe-started
test "$(docker exec "${container}" /command/s6-svstat -o up,ready /run/service/ready-probe)" = 'true false'
wait_for has_health unhealthy
docker exec "${container}" touch /tmp/ready-probe-release
wait_for has_health healthy

# An enabled legacy service participates in health and can recover after a stop.
docker exec "${container}" /command/s6-svc -d /run/service/legacy-enabled
wait_for has_health unhealthy
docker exec "${container}" /command/s6-svc -u /run/service/legacy-enabled
wait_for has_health healthy

# The oneshot's state matters even while all longruns are still running.
docker exec "${container}" /command/s6-rc -d change setup-probe
wait_for has_health unhealthy
docker exec "${container}" /command/s6-rc -u change setup-probe
wait_for has_health healthy

# A stopped required longrun stays active in the s6-rc state. Hold it down
# past the former ten-second restart guard to isolate the running check.
docker exec "${container}" /command/s6-svc -d /run/service/restart-probe
sleep 11
expect_probe_failure 's6 service is not running: restart-probe'
wait_for has_health unhealthy
docker exec "${container}" /command/s6-svc -u /run/service/restart-probe
wait_for has_health healthy

# Require two actual crashes and sample while the next process has been up
# long enough to pass the former ten-second restart guard.
docker exec "${container}" sh -c 'echo 15 > /tmp/restart-probe-crash'
docker exec "${container}" /command/s6-svc -r /run/service/restart-probe
wait_for docker exec "${container}" sh -c '
    deaths=$(/command/s6-svdt /run/service/restart-probe | grep -c " exitcode 1$")
    [ "$deaths" -ge 2 ]
'
wait_for docker exec "${container}" sh -c '
    set -- $(/command/s6-svstat -o up,updownfor /run/service/restart-probe)
    [ "$1" = true ] && [ "$2" -gt 10 ]
'
expect_probe_failure 's6 service exited repeatedly: restart-probe'
wait_for has_health unhealthy
docker exec "${container}" rm /tmp/restart-probe-crash
wait_for has_health healthy

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
