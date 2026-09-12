#!/usr/bin/env bash

# Runtime acceptance for the opencodex Feature.
#
# Builds a clean devcontainer that installs the Feature at a pinned version
# beside Caddy, then proves the proxy runs as the service user under s6, the
# Caddy fragment admits the dashboard through OpenCodex's Host and Origin
# gates, and `ocx update` replaces the package while s6 holds the proxy down
# and restarts it on the new version.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
image="${1:-devcontainers-opencodex-runtime:test}"
name="opencodex-runtime-test-${RANDOM}-$$"
port=10100
caddy_port=18080
dns_name=ocx.test-container.example.test
pinned_version=2.50.0
workspace="$(mktemp -d)"

DOCKER_CONFIG="${workspace}/docker"
export DOCKER_CONFIG
mkdir -p "${DOCKER_CONFIG}"
printf '{}' >"${DOCKER_CONFIG}/config.json"

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

cleanup() {
    docker stop "${name}" >/dev/null 2>&1 || true
    docker rm "${name}" >/dev/null 2>&1 || true
    rm -rf "${workspace}"
}
trap cleanup EXIT

as_user() {
    docker exec --user vscode --env HOME=/home/vscode "${name}" "$@"
}

wait_for_health() {
    for _ in $(seq 1 120); do
        if docker exec "${name}" curl --fail --silent "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

latest_version="$(npm view @bitkyc08/opencodex version)"
[ -n "${latest_version}" ] || fail "Unable to resolve the latest OpenCodex version."
[ "${latest_version}" != "${pinned_version}" ] \
    || fail "The pinned version ${pinned_version} is already latest; pick an older pin."
printf 'Pinned %s, latest resolves to %s.\n' "${pinned_version}" "${latest_version}"

mkdir -p "${workspace}/.devcontainer"
cp -a "${repo_root}/src/features/opencodex" "${workspace}/.devcontainer/opencodex"
cp -a "${repo_root}/src/features/caddy" "${workspace}/.devcontainer/caddy"

cat >"${workspace}/.devcontainer/devcontainer.json" <<EOF2
{
    "image": "ghcr.io/wyrd-company/devcontainers/base:noble",
    "features": {
        "./caddy": {},
        "./opencodex": {
            "version": "${pinned_version}",
            "port": "${port}",
            "dnsName": "${dns_name}"
        }
    }
}
EOF2

devcontainer build \
    --workspace-folder "${workspace}" \
    --image-name "${image}" >/dev/null

docker run --detach --name "${name}" "${image}" >/dev/null

wait_for_health || fail "Proxy did not answer on port ${port} within the startup window."

installed_version="$(as_user ocx --version)"
[ "${installed_version}" = "opencodex ${pinned_version}" ] \
    || fail "Feature installed '${installed_version}' rather than 'opencodex ${pinned_version}'."

# Match the npm launcher that runs the proxy; 's6-supervise opencodex' would otherwise
# resolve to the root-owned supervisor.
proxy_pid="$(docker exec "${name}" pgrep --full -- '/.local/bin/ocx start --port' | head -n 1)"
[ -n "${proxy_pid}" ] || fail "No OpenCodex proxy process is running in the container."
service_user="$(docker exec "${name}" ps -o user= -p "${proxy_pid}" | tr -d ' ')"
[ "${service_user}" = vscode ] \
    || fail "The proxy runs as '${service_user}' rather than the service user."

# Exercise the Caddy fragment on a plain HTTP listener so the check does not need
# the DNS name to resolve or a certificate to issue. Only the site address changes.
docker exec "${name}" bash -c "
    { printf '{\n    admin off\n}\n'; sed 's|^${dns_name} {|http://127.0.0.1:${caddy_port} {|' /etc/caddy/conf.d/opencodex.caddy; } >/tmp/opencodex-test.caddy
    caddy validate --config /tmp/opencodex-test.caddy --adapter caddyfile >/dev/null
    nohup caddy run --config /tmp/opencodex-test.caddy --adapter caddyfile >/tmp/opencodex-test-caddy.log 2>&1 &
" || fail "Unable to start the Caddy probe listener."
for _ in $(seq 1 30); do
    if docker exec "${name}" curl --silent --output /dev/null "http://127.0.0.1:${caddy_port}/healthz"; then
        break
    fi
    sleep 1
done

probe() {
    local origin="$1"
    shift
    local curl_args=(--silent --output /dev/null --write-out '%{http_code}')
    curl_args+=(--header "Authorization: Bearer ${admin_token}")
    if [ -n "${origin}" ]; then
        curl_args+=(--header "Origin: ${origin}")
    fi
    docker exec "${name}" curl "${curl_args[@]}" "http://127.0.0.1:${caddy_port}/api/startup-health"
}

admin_token="$(as_user cat /home/vscode/.opencodex/admin-api-token)"
[ -n "${admin_token}" ] || fail "OpenCodex did not mint an admin token."

direct_status="$(docker exec "${name}" curl --silent --output /dev/null --write-out '%{http_code}' \
    --header "Authorization: Bearer ${admin_token}" \
    --header "Host: ${dns_name}" "http://127.0.0.1:${port}/api/startup-health")"
[ "${direct_status}" = 403 ] \
    || fail "OpenCodex admitted a non-loopback Host directly (${direct_status}); the Caddy rewrite is untested."

status="$(probe '')"
[ "${status}" = 200 ] || fail "Management request through Caddy without an Origin returned ${status}."
status="$(probe "https://${dns_name}")"
[ "${status}" = 200 ] || fail "Dashboard Origin through Caddy returned ${status}."
status="$(probe https://other.example.test)"
[ "${status}" = 403 ] || fail "Foreign Origin through Caddy returned ${status} rather than 403."
printf 'Caddy fragment admits the dashboard and refuses foreign origins.\n'

proxy_running() {
    docker exec "${name}" pgrep --full -- '/.local/bin/ocx start --port' >/dev/null 2>&1
}

# ocx update: the wrapper takes a hold, OpenCodex stops the proxy and swaps the
# package, then s6 restarts the proxy on the new version. While the hold exists no
# proxy may run; sample that from outside for the whole update.
as_user ocx update >"${workspace}/update.log" 2>&1 &
update_pid=$!
saw_hold=0
while kill -0 "${update_pid}" 2>/dev/null; do
    if docker exec "${name}" sh -c 'ls -A /run/opencodex/holds 2>/dev/null | grep -q .'; then
        saw_hold=1
        if ! docker exec "${name}" test -e /home/vscode/.opencodex/ocx.pid && proxy_running; then
            fail "A proxy process ran while an update hold existed."
        fi
    fi
    sleep 0.5
done
wait "${update_pid}" || { cat "${workspace}/update.log"; fail "ocx update failed."; }
[ "${saw_hold}" -eq 1 ] || fail "ocx update never wrote a hold file."
grep -q "Updated to v${latest_version}" "${workspace}/update.log" \
    || { cat "${workspace}/update.log"; fail "ocx update did not report the new version."; }
docker exec "${name}" sh -c '! ls -A /run/opencodex/holds 2>/dev/null | grep -q .' \
    || fail "A hold file remained after ocx update."

updated_version="$(as_user ocx --version)"
[ "${updated_version}" = "opencodex ${latest_version}" ] \
    || fail "After update ocx reports '${updated_version}' rather than 'opencodex ${latest_version}'."

wait_for_health || fail "Proxy did not return after ocx update."
new_pid="$(docker exec "${name}" pgrep --full -- '/.local/bin/ocx start --port' | head -n 1)"
[ -n "${new_pid}" ] || fail "No OpenCodex proxy process is running after the update."
[ "${new_pid}" != "${proxy_pid}" ] || fail "The proxy process was not restarted by the update."
new_user="$(docker exec "${name}" ps -o user= -p "${new_pid}" | tr -d ' ')"
[ "${new_user}" = vscode ] || fail "The restarted proxy runs as '${new_user}'."
docker exec "${name}" sh -c "tr '\\0' ' ' </proc/${new_pid}/cmdline" | grep -q -- "--port ${port}" \
    || fail "The restarted proxy is not listening on the configured port."
printf 'Proxy restarted as vscode on %s after ocx update.\n' "${updated_version}"

# An operator hold outlives an update and keeps the proxy down until removed. A stale
# hold from a vanished process must not.
as_user touch /run/opencodex/paused
as_user sh -c 'echo 999999 >/run/opencodex/holds/999999'
as_user ocx stop >/dev/null 2>&1 || true
sleep 5
proxy_running && fail "The proxy restarted while /run/opencodex/paused existed."
as_user ocx update --tag preview >"${workspace}/update-preview.log" 2>&1 \
    || { cat "${workspace}/update-preview.log"; fail "ocx update --tag preview failed while paused."; }
sleep 3
proxy_running && fail "ocx update removed the operator hold."
docker exec "${name}" test -e /run/opencodex/paused || fail "ocx update deleted /run/opencodex/paused."
as_user rm /run/opencodex/paused
wait_for_health || fail "Proxy did not return after the operator hold was removed."
docker exec "${name}" test ! -e /run/opencodex/holds/999999 || fail "The launcher kept a stale hold."
preview_version="$(as_user ocx --version)"
case "${preview_version}" in
    *-preview.*) ;;
    *) fail "ocx update --tag preview installed '${preview_version}'." ;;
esac
printf 'Operator hold survived an update; stale hold was discarded; now on %s.\n' "${preview_version}"

printf 'OpenCodex runtime checks passed.\n'
