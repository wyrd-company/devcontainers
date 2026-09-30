#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
base_image="${BASE_IMAGE:-$("${repo_root}/scripts/build-base-image.sh" noble)}"
image="${1:-devcontainers-codex-runtime:test}"
name="codex-runtime-test-${RANDOM}-$$"
cleanup() {
    docker rm -f "${name}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker build --file "${repo_root}/test/features/codex-cli/runtime.Dockerfile" \
    --build-arg "BASE_IMAGE=${base_image}" --tag "${image}" "${repo_root}"
"${repo_root}/scripts/check-sudo-no-all.sh" "${image}"
docker run --detach --name "${name}" --env SAMPLE_RUNTIME_VALUE=sample-runtime-value --env CODEX_INTERNAL_APP_SERVER_REMOTE_CONTROL_DISABLED=0 "${image}" >/dev/null
for _ in $(seq 1 60); do
    if docker exec "${name}" test -S /home/vscode/.codex/app-server-control/app-server-control.sock; then break; fi
    sleep 0.5
done
docker exec "${name}" test -S /home/vscode/.codex/app-server-control/app-server-control.sock
pid="$(docker exec "${name}" pgrep -f '^/home/vscode/.local/lib/node_modules/@openai/codex.*app-server --listen unix://' | head -n 1)"
test -n "${pid}"
test "$(docker exec "${name}" ps -o user= -p "${pid}" | tr -d ' ')" = vscode
for expected in HOME=/home/vscode USER=vscode SAMPLE_RUNTIME_VALUE=sample-runtime-value; do
    docker exec --user vscode "${name}" sh -c 'tr "\0" "\n" <"/proc/$1/environ" | grep -Fxq "$2"' sh "${pid}" "${expected}"
done
docker cp "${repo_root}/test/features/codex-cli/probe.mjs" "${name}:/opt/codex-probe/probe.mjs"
docker exec --user vscode --env HOME=/home/vscode "${name}" node /opt/codex-probe/probe.mjs
docker exec "${name}" /command/s6-svc -r /run/service/codex-cli
for _ in $(seq 1 60); do
    if ! docker exec "${name}" test -e "/proc/${pid}"; then break; fi
    sleep 0.5
done
if docker exec "${name}" test -e "/proc/${pid}"; then
    echo "The previous app-server remained after restart." >&2
    exit 1
fi
for _ in $(seq 1 60); do
    if docker exec "${name}" test -S /home/vscode/.codex/app-server-control/app-server-control.sock; then break; fi
    sleep 0.5
done
docker exec --user vscode --env HOME=/home/vscode "${name}" node /opt/codex-probe/probe.mjs

assert_install_rejected() {
    local expected="$1"
    shift
    local output
    if output="$(docker run --rm --entrypoint /bin/bash \
        --volume "${repo_root}/src/features/codex-cli:/feature:ro" "${image}" \
        -c 'env "$@" /feature/install.sh' bash "$@" 2>&1)"; then
        echo "Invalid Feature configuration was accepted." >&2
        exit 1
    fi
    printf '%s\n' "${output}" | grep -Fq "${expected}"
}
assert_install_rejected 'execServerPort must be an integer' EXECSERVERPORT=sample-invalid
assert_install_rejected 'appServerPort must be an integer' APPSERVERPORT=0
assert_install_rejected 'appServerPort and execServerPort must differ' DNSNAME=sample-codex.example.test EXECSERVER=true APPSERVERPORT=4501
assert_install_rejected 'dnsName requires an enabled' DNSNAME=sample-codex.example.test STARTAPPSERVER=false EXECSERVER=false
assert_install_rejected 'dnsName requires the Caddy Feature' DNSNAME=sample-codex.example.test
assert_install_rejected 'dnsName contains unsupported DNS characters' DNSNAME=$'sample-codex.example.test\n}'
assert_install_rejected 'Unable to parse execServer arguments' EXECSERVER='--ws-issuer sample; sample-command'
assert_install_rejected 'startAppServer must be true or false' STARTAPPSERVER=sample-invalid
assert_install_rejected 'remoteControl must be true or false' REMOTECONTROL=sample-invalid
assert_install_rejected 'remoteControl requires startAppServer' STARTAPPSERVER=false REMOTECONTROL=true
assert_install_rejected "Requested service user 'sample-missing-user' does not exist" SERVICEUSER=sample-missing-user

docker run --rm --entrypoint /bin/bash \
    --volume "${repo_root}/src/features/codex-cli:/feature:ro" "${image}" -c '
    set -euo pipefail
    source /feature/common.sh
    test "$(_REMOTE_USER=sample-missing-user _CONTAINER_USER=vscode pick_devcontainer_user automatic)" = vscode
    test "$(_REMOTE_USER= _CONTAINER_USER=sample-missing-user pick_devcontainer_user automatic)" = vscode
    userdel vscode
    test "$(_REMOTE_USER= _CONTAINER_USER= pick_devcontainer_user automatic)" = root
'
echo 'Codex service runtime, restart, environment, and option checks passed.'
"${repo_root}/scripts/test-codex-exec-runtime.sh" "${base_image}"
"${repo_root}/scripts/test-codex-caddy-runtime.sh" "${base_image}"
