#!/usr/bin/env bash

# Runtime acceptance for the t3code-server Feature.
#
# Two clean devcontainers are built from the Feature source and started:
#
# 1. The fork: packageSource github:wyrd-company/t3code with version latest.
#    Proves the console is served by that installation as the service user.
# 2. Upstream: an exact release archive. Proves the service user can run the
#    update command through sudo and nothing else, that the update moves the
#    service to a newer release archive, and that the console comes back on
#    it.
#
# Scope stops at the console. Whether a client can register its own MCP
# endpoint and have an agent call it is proven by the fork's own consumer probe,
# apps/server/scripts/consumer-live-probe.sh, which drives a session through the
# server rather than running a harness beside it.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
image_prefix="${1:-devcontainers-t3code-runtime}"
port=3773
upstream_old_version=0.0.42
# The newest upstream release with a Linux archive that is newer than the
# stable one above; nightlies are retained, stable 0.0.43 replaces this when
# it ships.
upstream_new_version=0.0.43-nightly.20260922.2096
workspace="$(mktemp -d)"
name=""

# Isolate the Docker config so the build resolves images anonymously and does
# not inherit a host credential helper.
DOCKER_CONFIG="${workspace}/docker"
export DOCKER_CONFIG
mkdir -p "${DOCKER_CONFIG}"
printf '{}' >"${DOCKER_CONFIG}/config.json"

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

console_url="http://127.0.0.1:${port}/"

fetch_console() {
    docker exec "${name}" curl \
        --fail \
        --silent \
        --show-error \
        --connect-timeout 2 \
        --max-time 5 \
        "${console_url}"
}

report_container_state() {
    printf '%s\n' 'T3 Code container state:' >&2
    docker inspect --format '{{.State.Status}} exit={{.State.ExitCode}} error={{.State.Error}}' \
        "${name}" >&2 || true
    printf '%s\n' 'T3 Code service processes:' >&2
    docker exec "${name}" ps -ef >&2 || true
    printf '%s\n' 'T3 Code container log:' >&2
    docker logs "${name}" >&2 || true
}

stop_container() {
    if [ -n "${name}" ]; then
        docker stop "${name}" >/dev/null 2>&1 || true
        docker rm "${name}" >/dev/null 2>&1 || true
        name=""
    fi
}

cleanup() {
    stop_container
    rm -rf "${workspace}"
}
trap cleanup EXIT

# Builds an image from the Feature source with the given feature options
# (a JSON object) and starts it as the current container.
start_container() {
    local scenario="$1" options="$2"
    local image="${image_prefix}:${scenario}" project="${workspace}/${scenario}"

    mkdir -p "${project}/.devcontainer"
    cp -a "${repo_root}/src/features/t3code-server" "${project}/.devcontainer/t3code-server"
    cat >"${project}/.devcontainer/devcontainer.json" <<EOF
{
    "image": "ghcr.io/wyrd-company/devcontainers/base:noble",
    "features": {
        "./t3code-server": ${options}
    }
}
EOF
    devcontainer build \
        --workspace-folder "${project}" \
        --image-name "${image}" >/dev/null
    printf 'Built T3 Code %s image.\n' "${scenario}"

    name="t3code-runtime-test-${scenario}-${RANDOM}-$$"
    docker run --detach --name "${name}" "${image}" >/dev/null
    printf 'Started T3 Code %s container.\n' "${scenario}"
}

# Waits for the console within a bounded window; $1 names the phase in the
# failure message.
wait_for_console() {
    local phase="$1" ready=false deadline
    deadline=$((SECONDS + 120))
    while ((SECONDS < deadline)); do
        if fetch_console >/dev/null 2>&1; then
            ready=true
            break
        fi
        sleep 1
    done
    if [ "${ready}" != true ]; then
        report_container_state
        fail "Console did not serve on port ${port} within the 120-second startup window (${phase})."
    fi
    printf 'T3 Code console became ready (%s).\n' "${phase}"
}

# 's6-supervise t3code-server' and the probing shell itself also mention t3,
# so match the whole command line. An archive runtime runs from the versions
# tree; an npm runtime's shim execs the npm-installed executable.
serve_pid() {
    docker exec "${name}" pgrep --full --exact -- '.*/t3 serve .*' | head -n 1 || true
}

assert_serve() {
    local expected_version="$1" expected_mode="$2" t3_pid service_user cmdline

    t3_pid="$(serve_pid)"
    [ -n "${t3_pid}" ] || fail "No T3 Code serve process is running in the container."

    service_user="$(docker exec "${name}" ps -o user= -p "${t3_pid}" | tr -d ' ')"
    [ "${service_user}" = vscode ] \
        || fail "T3 Code serve runs as '${service_user}' rather than the service user."

    # An archive runtime names its version on the command line; an npm shim
    # does not, and its version is already proven through `t3 --version`.
    cmdline="$(docker exec "${name}" sh -c "tr '\\0' ' ' </proc/${t3_pid}/cmdline")"
    if printf '%s' "${cmdline}" | grep -q -- '/.t3/runtime/versions/'; then
        printf '%s' "${cmdline}" | grep -q -- "/.t3/runtime/versions/${expected_version}/t3 serve" \
            || fail "T3 Code serve is not running the ${expected_version} runtime: ${cmdline}"
    fi

    if [ -n "${expected_mode}" ]; then
        printf '%s' "${cmdline}" | grep -q -- "--mode=${expected_mode}" \
            || fail "T3 Code serve is not running the ${expected_mode} runtime mode: ${cmdline}"
    fi
}

assert_console_html() {
    local console
    if ! console="$(fetch_console)"; then
        report_container_state
        fail "Console stopped responding after it became ready."
    fi
    printf '%s' "${console}" | grep -qi '<!doctype html' \
        || fail "Console root did not return an HTML document."
}

# --- Scenario 1: the fork, latest -------------------------------------------

# Resolve independently of the container so the assertion below can disagree
# with what the Feature actually installed.
mapfile -t resolution < <(
    python3 "${repo_root}/src/features/t3code-server/resolve-package-source.py" \
        github:wyrd-company/t3code latest x64
)
expected_version="${resolution[2]}"
printf 'Fork latest resolves to %s (%s).\n' "${expected_version}" "${resolution[0]}"

start_container fork "$(cat <<EOF
{
    "packageSource": "github:wyrd-company/t3code",
    "version": "latest",
    "serveMode": "web",
    "host": "127.0.0.1",
    "port": "${port}"
}
EOF
)"
wait_for_console "fork ${expected_version}"

installed_version="$(docker exec "${name}" /usr/local/bin/t3 --version)"
[ "${installed_version}" = "t3 v${expected_version}" ] \
    || fail "Feature installed '${installed_version}' but latest resolves to 't3 v${expected_version}'."

assert_serve "${expected_version}" web
assert_console_html
printf 'Console served by %s as vscode.\n' "${installed_version}"
stop_container

# --- Scenario 2: upstream archive, then an in-container update ---------------

start_container upstream "$(cat <<EOF
{
    "version": "${upstream_old_version}",
    "serveMode": "web",
    "host": "127.0.0.1",
    "port": "${port}"
}
EOF
)"
wait_for_console "upstream ${upstream_old_version}"

installed_version="$(docker exec "${name}" /usr/local/bin/t3 --version)"
[ "${installed_version}" = "t3 v${upstream_old_version}" ] \
    || fail "Feature installed '${installed_version}' rather than 't3 v${upstream_old_version}'."
assert_serve "${upstream_old_version}" web
old_pid="$(serve_pid)"

# The service user updates through sudo. On an image that restricts the
# user's sudo, the Feature's grant is the only reason this is allowed, and it
# must not open anything else; an image with unrestricted sudo cannot show
# that, so the negative probe is skipped there.
docker exec --user vscode "${name}" sudo -n -l /usr/local/bin/t3code-server-update >/dev/null \
    || fail "sudo does not let the service user run t3code-server-update."
if docker exec --user vscode "${name}" sudo -n -l /bin/true >/dev/null 2>&1; then
    printf 'Image grants the service user unrestricted sudo; skipping the exclusivity probe.\n'
elif docker exec --user vscode "${name}" sudo -n -l /usr/local/lib/t3code-server/t3code-runtime >/dev/null 2>&1; then
    fail "sudo lets the service user run more than t3code-server-update."
fi
docker exec --user vscode "${name}" sudo -n /usr/local/bin/t3code-server-update "${upstream_new_version}" \
    || { report_container_state; fail "t3code-server-update ${upstream_new_version} failed."; }

# The restart tears the old server down before the new one listens, so wait
# for the old process to go before waiting for the console.
deadline=$((SECONDS + 60))
while ((SECONDS < deadline)) && docker exec "${name}" test -d "/proc/${old_pid}"; do
    sleep 1
done
docker exec "${name}" test ! -d "/proc/${old_pid}" \
    || fail "The previous T3 Code serve process (pid ${old_pid}) survived the update restart."
wait_for_console "updated ${upstream_new_version}"

installed_version="$(docker exec "${name}" /usr/local/bin/t3 --version)"
[ "${installed_version}" = "t3 v${upstream_new_version}" ] \
    || fail "After the update, t3 reports '${installed_version}' rather than 't3 v${upstream_new_version}'."
status="$(docker exec "${name}" /usr/local/bin/t3code-server-update --status)"
printf '%s\n' "${status}" | grep -q "^selected version: ${upstream_new_version}$" \
    || fail "The update command does not report ${upstream_new_version} as selected: ${status}"
assert_serve "${upstream_new_version}" web
assert_console_html
printf 'Console served by %s after the in-container update.\n' "${installed_version}"

printf 'T3 Code runtime checks passed.\n'
