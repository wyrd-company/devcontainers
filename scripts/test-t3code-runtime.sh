#!/usr/bin/env bash

# Runtime acceptance for the t3code-server Feature.
#
# Three clean devcontainers are built from the Feature source and started:
#
# 1. npm: a version range installed through npm. Proves the console is served
#    by that installation as the service user, and that an s6 restart stops
#    the server rather than only the npm package's Node shim, and brings the
#    console back.
# 2. Release archive: an exact upstream version. Proves the service user can
#    run the update command through sudo and nothing else, that the update
#    moves the service to a newer release archive as the service user, and
#    that the console comes back on it.
#
# 3. Native launcher: authenticated client RPC updates, SQLite rollback,
#    persistent selection across s6 restart, and deferred local maintenance.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
base_image="${BASE_IMAGE:-$("${repo_root}/scripts/build-base-image.sh" noble)}"
image_prefix="${1:-devcontainers-t3code-runtime}"
port=3773
npm_range="<=0.0.45"
npm_version=0.0.45
upstream_old_version=0.0.42
upstream_new_version=0.0.45
workspace="$(mktemp -d)"
name=""
runtime_volume=""

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
    if [ -n "${runtime_volume}" ]; then
        docker volume rm "${runtime_volume}" >/dev/null
    fi
    rm -rf "${workspace}"
}
trap cleanup EXIT

# Builds an image from the Feature source with the given feature options
# (a JSON object) and starts it as the current container.
start_container() {
    local scenario="$1" options="$2"
    local image="${image_prefix}:${scenario}" project="${workspace}/${scenario}"
    local -a mount_args=()

    mkdir -p "${project}/.devcontainer"
    cp -a "${repo_root}/src/features/t3code-server" "${project}/.devcontainer/t3code-server"
    cat >"${project}/.devcontainer/devcontainer.json" <<EOF
{
    "image": "${base_image}",
    "features": {
        "./t3code-server": ${options}
    }
}
EOF
    devcontainer build \
        --workspace-folder "${project}" \
        --image-name "${image}" >/dev/null
    printf 'Built T3 Code %s image.\n' "${scenario}"
    "${repo_root}/scripts/check-sudo-no-all.sh" "${image}"

    name="t3code-runtime-test-${scenario}-${RANDOM}-$$"
    if [ "${scenario}" = native ]; then
        runtime_volume="sample-t3code-runtime-${RANDOM}-$$"
        docker volume create "${runtime_volume}" >/dev/null
        mount_args=(--mount "type=volume,source=${runtime_volume},target=/home/vscode/.t3")
    fi
    docker run --detach --name "${name}" \
        "${mount_args[@]}" --env T3CODE_MODE=desktop --env T3CODE_HOME=/tmp/sample-ignored "${image}" >/dev/null
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
# so match the whole command line.
serve_pid() {
    docker exec "${name}" pgrep --full --exact -- '.*/t3 serve( .*)?' | head -n 1 || true
}

assert_serve() {
    local expected_version="$1" expected_mode="$2" t3_pid service_user cmdline environment

    t3_pid="$(serve_pid)"
    [ -n "${t3_pid}" ] || fail "No T3 Code serve process is running in the container."

    service_user="$(docker exec "${name}" ps -o user= -p "${t3_pid}" | tr -d ' ')"
    [ "${service_user}" = vscode ] \
        || fail "T3 Code serve runs as '${service_user}' rather than the service user."

    # Both kinds of runtime run from their own version directory: an archive
    # runtime's executable sits at its top, and an npm runtime's sits inside
    # its own npm prefix there.
    cmdline="$(docker exec --user vscode "${name}" sh -c "tr '\\0' ' ' </proc/${t3_pid}/cmdline")"
    printf '%s' "${cmdline}" | grep -q -- "/.t3/runtime/versions/${expected_version}/" \
        || fail "T3 Code serve is not running the ${expected_version} runtime: ${cmdline}"

    environment="$(docker exec --user vscode "${name}" sh -c "tr '\\0' '\\n' </proc/${t3_pid}/environ" | sed -n '/^HOME=/p; /^USER=/p; /^LOGNAME=/p; /^T3CODE_MODE=/p; /^T3CODE_HOME=/p; /^T3CODE_HOST=/p; /^T3CODE_PORT=/p')"
    for expected in HOME=/home/vscode USER=vscode LOGNAME=vscode; do
        grep -qx "${expected}" <<<"${environment}" || fail "Service environment lacks ${expected}."
    done
    if [ -n "${expected_mode}" ]; then
        if [[ "${cmdline}" != *"--mode=${expected_mode}"* ]]; then
            for expected in "T3CODE_MODE=${expected_mode}" T3CODE_HOME=/home/vscode/.t3 T3CODE_HOST=127.0.0.1 "T3CODE_PORT=${port}"; do
                grep -qx "${expected}" <<<"${environment}" || fail "Native service environment lacks ${expected}."
            done
        fi
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

# --- Scenario 1: an npm range ----------------------------------------------

start_container npm "$(cat <<EOF
{
    "version": "${npm_range}",
    "serveMode": "web",
    "host": "127.0.0.1",
    "port": "${port}"
}
EOF
)"
wait_for_console "npm ${npm_range}"

installed_version="$(docker exec "${name}" /usr/local/bin/t3 --version)"
[ "${installed_version}" = "t3 v${npm_version}" ] \
    || fail "Feature installed '${installed_version}' but ${npm_range} resolves to 't3 v${npm_version}'."

assert_serve "${npm_version}" web
assert_console_html
printf 'Console served by %s as vscode.\n' "${installed_version}"

# A restart must stop the server it supervises. A wrapper that leaves the
# server behind keeps the port bound and the replacement crash-loops.
old_pid="$(serve_pid)"
docker exec "${name}" /command/s6-svc -r /run/service/t3code-server
deadline=$((SECONDS + 30))
while docker exec "${name}" test -d "/proc/${old_pid}"; do
    if ((SECONDS >= deadline)); then
        report_container_state
        fail "T3 Code serve process ${old_pid} survived an s6 restart."
    fi
    sleep 1
done
wait_for_console "npm after an s6 restart"
stop_container

# --- Scenario 2: release archive, then an in-container update ---------------

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

# The service user updates through sudo. The base image restricts the user's
# sudo, so the Feature's grant is the only reason this is allowed, and it must
# not open anything else.
docker exec --user vscode "${name}" sudo -n -l /usr/local/bin/t3code-server-update >/dev/null \
    || fail "sudo does not let the service user run t3code-server-update."
for command in /bin/true /usr/local/lib/t3code-server/t3code-runtime; do
    if docker exec --user vscode "${name}" sudo -n -l "${command}" >/dev/null 2>&1; then
        fail "sudo lets the service user run ${command}, not only t3code-server-update."
    fi
done
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
root_owned="$(docker exec "${name}" find /home/vscode/.t3/runtime -user root)"
[ -z "${root_owned}" ] || fail "The update left root-owned files in the runtime tree: ${root_owned}"
printf 'Console served by %s after the in-container update.\n' "${installed_version}"

stop_container

# --- Scenario 3: authenticated native update, rollback and local maintenance ---
start_container native '{"version":"0.1.1","serveMode":"web","host":"127.0.0.1","port":"3773"}'
wait_for_console "native launcher"
assert_serve 0.1.1 web
for file in native-update.cjs failed-runtime.cjs; do
    docker cp "${repo_root}/test/features/t3code-server/${file}" "${name}:/tmp/${file}"
done
docker exec --user vscode "${name}" node /tmp/native-update.cjs
launcher_pid="$(docker exec "${name}" pgrep --full --exact '.*/service-launcher __service-launcher')"
old_pid="$(serve_pid)"
# A later successful native update must expire this deferred local selection.
docker exec --user vscode "${name}" sudo -n t3code-server-update --force --no-restart 0.1.1
docker exec --user vscode "${name}" node /tmp/native-update.cjs 0.1.2

wait_for_outcome() {
    local expected="$1" deadline=$((SECONDS + 120))
    while ((SECONDS < deadline)); do
        if docker exec "${name}" python3 -c 'import json,sys; s=json.load(open("/home/vscode/.t3/runtime/service-state.json")); sys.exit(s.get("update", {}).get("status") != sys.argv[1])' "${expected}"; then
            return
        fi
        sleep 1
    done
    report_container_state
    fail "Native update did not reach ${expected}."
}
wait_for_outcome committed
wait_for_console "native update"
assert_serve 0.1.2 web
[ "$(docker exec "${name}" /usr/local/bin/t3 --version)" = 't3 v0.1.2' ] || fail "CLI did not follow native state."
docker exec "${name}" test ! -d "/proc/${old_pid}" || fail "Old child survived native update."
[ "$(docker exec "${name}" pgrep --full --exact '.*/service-launcher __service-launcher')" = "${launcher_pid}" ] || fail "Native update replaced the stable launcher."
# The stable launcher and newly committed version must survive an s6 restart.
docker exec "${name}" /command/s6-svc -wD -d /run/service/t3code-server
docker exec "${name}" /command/s6-svc -u /run/service/t3code-server
wait_for_console "native update after s6 restart"
assert_serve 0.1.2 web

docker exec "${name}" test ! -e /home/vscode/.t3/runtime/queued-runtime

# Feature installation occurs during image build, before runtime mounts. A
# persisted native selection must mask the older state in the pinned image.
stop_container
name="t3code-runtime-test-recreated-${RANDOM}-$$"
docker run --detach --name "${name}" \
    --mount "type=volume,source=${runtime_volume},target=/home/vscode/.t3" \
    --env T3CODE_MODE=desktop --env T3CODE_HOME=/tmp/sample-ignored "${image_prefix}:native" >/dev/null
wait_for_console "persisted native update with the pinned 0.1.1 image"
assert_serve 0.1.2 web
for file in native-update.cjs failed-runtime.cjs; do
    docker cp "${repo_root}/test/features/t3code-server/${file}" "${name}:/tmp/${file}"
done

# The trial writes to SQLite, then exits before activation. Read back its
# external marker and the restored database so a failed preflight cannot pass.
docker exec --user vscode "${name}" bash -c '
    dir=/home/vscode/.t3/runtime/versions/0.1.3-sample.0
    mkdir -p "$dir"
    cp /tmp/failed-runtime.cjs "$dir/t3"
    chmod +x "$dir/t3"
    echo 0.1.3-sample.0 >"$dir/.install-complete"
'
docker exec --user vscode "${name}" node -e '
    const {DatabaseSync}=require("node:sqlite");
    const db=new DatabaseSync("/home/vscode/.t3/userdata/statev2.sqlite");
    db.exec("CREATE TABLE sample_restore (value INTEGER); INSERT INTO sample_restore VALUES (1)");
    db.close();
'
docker exec --user vscode "${name}" node /tmp/native-update.cjs 0.1.3-sample.0
wait_for_outcome rolled-back
wait_for_console "native rollback"
docker exec "${name}" test -f /home/vscode/.t3/sample-trial-started
docker exec --user vscode "${name}" node -e '
    const {DatabaseSync}=require("node:sqlite");
    const db=new DatabaseSync("/home/vscode/.t3/userdata/statev2.sqlite");
    require("node:assert/strict").equal(db.prepare("SELECT value FROM sample_restore").get().value,1);
    db.close();
'
assert_serve 0.1.2 web

# Deferred local maintenance must not replace the live runtime or native state.
old_pid="$(serve_pid)"
docker exec --user vscode "${name}" sudo -n t3code-server-update --force --no-restart 0.1.1
docker exec "${name}" test -d "/proc/${old_pid}"
[ "$(docker exec "${name}" t3 --version)" = 't3 v0.1.2' ] || fail "Deferred maintenance changed the live selection."
status="$(docker exec "${name}" t3code-server-update --status)"
[[ "${status}" == *'queued version: 0.1.1'* ]] || fail "Deferred version is absent from status."
docker exec "${name}" /command/s6-svc -wD -d /run/service/t3code-server
docker exec "${name}" /command/s6-svc -u /run/service/t3code-server
wait_for_console "deferred local downgrade"
assert_serve 0.1.1 web
[ "$(docker exec "${name}" t3 --version)" = 't3 v0.1.1' ] || fail "Deferred maintenance was not applied."
# Cached local maintenance selects the release without starting a stopped service.
docker exec "${name}" /command/s6-svc -wD -d /run/service/t3code-server
maintenance="$(docker exec --user vscode "${name}" sudo -n t3code-server-update 0.1.2)"
[[ "${maintenance}" == *'Reusing the installed T3 Code 0.1.2 runtime.'* ]] || fail "Cached runtime was not reused."
[ "$(docker exec "${name}" /command/s6-svstat -o wantedup /run/service/t3code-server)" = false ] || fail "Local maintenance started a stopped service."
[ -z "$(serve_pid)" ] || fail "Local maintenance left a child running in the stopped service."
docker exec "${name}" /command/s6-svc -u /run/service/t3code-server
wait_for_console "cached local update after an explicit start"
assert_serve 0.1.2 web
root_owned="$(docker exec "${name}" find /home/vscode/.t3/runtime -user root)"
[ -z "${root_owned}" ] || fail "Native update or maintenance left root-owned runtime files."
# Status through sudo must read user-controlled links only as the service user.
# This is synthetic permission-fixture data, not a credential.
docker exec "${name}" sh -c 'echo sample-private-value >/root/sample-private-status; chmod 0600 /root/sample-private-status'
docker exec --user vscode "${name}" ln -s /root/sample-private-status /home/vscode/.t3/runtime/queued-runtime
if status="$(docker exec --user vscode "${name}" sudo -n t3code-server-update --status 2>&1)"; then
    fail "Privileged status accepted an unreadable queued-runtime link."
fi
[[ "${status}" != *sample-private-value* ]] || fail "Privileged status disclosed protected fixture data."
docker exec --user vscode "${name}" rm /home/vscode/.t3/runtime/queued-runtime
printf 'T3 Code runtime checks passed.\n' 
