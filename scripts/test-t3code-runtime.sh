#!/usr/bin/env bash

# Runtime acceptance for the t3code-server Feature consumed from the fork.
#
# Builds a clean devcontainer that installs the published Feature with
# packageSource github:wyrd-company/t3code and version latest, then proves the
# console is served by that installation.
#
# Scope stops at the console. Whether a client can register its own MCP
# endpoint and have an agent call it is proven by the fork's own consumer probe,
# apps/server/scripts/consumer-live-probe.sh, which drives a session through the
# server rather than running a harness beside it.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
image="${1:-devcontainers-t3code-runtime:test}"
name="t3code-runtime-test-${RANDOM}-$$"
port=3773
workspace="$(mktemp -d)"

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

cleanup() {
    docker stop "${name}" >/dev/null 2>&1 || true
    docker rm "${name}" >/dev/null 2>&1 || true
    rm -rf "${workspace}"
}
trap cleanup EXIT

# Resolve independently of the container so the assertion below can disagree
# with what the Feature actually installed.
mapfile -t resolution < <(
    python3 "${repo_root}/src/features/t3code-server/resolve-package-source.py" \
        github:wyrd-company/t3code latest
)
expected_version="${resolution[1]}"
printf 'Fork latest resolves to %s.\n' "${expected_version}"

mkdir -p "${workspace}/.devcontainer"
cp -a "${repo_root}/src/features/t3code-server" "${workspace}/.devcontainer/t3code-server"

cat >"${workspace}/.devcontainer/devcontainer.json" <<EOF
{
    "image": "ghcr.io/wyrd-company/devcontainers/base:noble",
    "features": {
        "./t3code-server": {
            "packageSource": "github:wyrd-company/t3code",
            "version": "latest",
            "serveMode": "web",
            "host": "127.0.0.1",
            "port": "${port}"
        }
    }
}
EOF

devcontainer build \
    --workspace-folder "${workspace}" \
    --image-name "${image}" >/dev/null
printf 'Built T3 Code runtime image.\n'

docker run --detach --name "${name}" "${image}" >/dev/null
printf 'Started T3 Code runtime container.\n'

ready=false
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
    fail "Console did not serve on port ${port} within the 120-second startup window."
fi
printf 'T3 Code console became ready.\n'

installed_version="$(docker exec "${name}" /usr/local/bin/t3 --version)"
[ "${installed_version}" = "t3 v${expected_version}" ] \
    || fail "Feature installed '${installed_version}' but latest resolves to 't3 v${expected_version}'."

linked_bin="$(docker exec "${name}" readlink -f /usr/local/bin/t3)"
[ "${linked_bin}" = /usr/local/lib/node_modules/t3/dist/bin.mjs ] \
    || fail "Global t3 link resolves outside the fork package: ${linked_bin}."

# Match the serve process itself; 's6-supervise t3code-server' also contains
# both words and would otherwise resolve to the root-owned supervisor.
t3_pid="$(docker exec "${name}" pgrep --full -- '/usr/local/bin/t3 serve --host' | head -n 1)"
[ -n "${t3_pid}" ] || fail "No T3 Code serve process is running in the container."

service_user="$(docker exec "${name}" ps -o user= -p "${t3_pid}" | tr -d ' ')"
[ "${service_user}" = vscode ] \
    || fail "T3 Code serve runs as '${service_user}' rather than the service user."

docker exec "${name}" sh -c "tr '\\0' ' ' </proc/${t3_pid}/cmdline" | grep -q -- '--mode=web' \
    || fail "T3 Code serve is not running the web runtime."

if ! console="$(fetch_console)"; then
    report_container_state
    fail "Console stopped responding after it became ready."
fi
printf '%s' "${console}" | grep -qi '<!doctype html' \
    || fail "Console root did not return an HTML document."

printf 'Console served by %s as vscode.\n' "${installed_version}"

printf 'T3 Code fork runtime checks passed.\n'
