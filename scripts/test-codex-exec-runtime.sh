#!/usr/bin/env bash
# ---
# relationships:
#   verifies: codex-cli
# ---
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
base_image="${1:-$("${repo_root}/scripts/build-base-image.sh" noble)}"
names=()
cleanup() {
    for name in "${names[@]}"; do docker rm -f "${name}" >/dev/null 2>&1 || true; done
}
trap cleanup EXIT
for mode in capability signed none; do
    case "${mode}" in
        capability) flags='--ws-auth capability-token --ws-token-file "/run/sample-secrets/exec token"' ;;
        signed) flags='--ws-auth signed-bearer-token --ws-shared-secret-file "/run/sample-secrets/exec key" --ws-issuer "sample issuer" --ws-audience sample-audience --ws-max-clock-skew-seconds 20' ;;
        none) flags=true ;;
    esac
    image="devcontainers-codex-exec-${mode}:test"
    name="codex-exec-runtime-${mode}-${RANDOM}-$$"
    names+=("${name}")
    docker build --file "${repo_root}/test/features/codex-cli/runtime.Dockerfile" \
        --build-arg "BASE_IMAGE=${base_image}" --build-arg "EXECSERVER=${flags}" \
        --tag "${image}" "${repo_root}"
    "${repo_root}/scripts/check-sudo-no-all.sh" "${image}"
    docker run --detach --name "${name}" --env SAMPLE_RUNTIME_VALUE=sample-runtime-value "${image}" >/dev/null
    for _ in $(seq 1 60); do
        if docker exec "${name}" bash -c 'exec 3<>/dev/tcp/127.0.0.1/4501' 2>/dev/null; then break; fi
        sleep 0.5
    done
    docker exec "${name}" bash -c 'exec 3<>/dev/tcp/127.0.0.1/4501'
    pid="$(docker exec "${name}" pgrep -f '^/home/vscode/.local/lib/node_modules/@openai/codex.*exec-server --listen ws://127.0.0.1:4501' | head -n 1)"
    test -n "${pid}"
    test "$(docker exec "${name}" ps -o user= -p "${pid}" | tr -d ' ')" = vscode
    for expected in HOME=/home/vscode USER=vscode SAMPLE_RUNTIME_VALUE=sample-runtime-value; do
        docker exec --user vscode "${name}" sh -c 'tr "\0" "\n" <"/proc/$1/environ" | grep -Fxq "$2"' sh "${pid}" "${expected}"
    done
    docker exec --user vscode --env "SAMPLE_EXEC_AUTH=${mode}" "${name}" node /opt/codex-probe/exec-probe.mjs
    if [ "${mode}" = capability ]; then
        docker exec --user vscode --env SAMPLE_ARGUMENT_PARSER=/usr/local/share/codex-cli-arguments/parse.cjs \
            --env NODE_PATH=/usr/local/share/codex-cli-arguments/node_modules "${name}" node --test /opt/codex-probe/arguments.test.cjs
    fi
    docker exec "${name}" /command/s6-svc -r /run/service/codex-exec-server
    for _ in $(seq 1 60); do
        if ! docker exec "${name}" test -e "/proc/${pid}"; then break; fi
        sleep 0.5
    done
    if docker exec "${name}" test -e "/proc/${pid}"; then
        echo 'The previous exec-server remained after restart.' >&2
        exit 1
    fi
    for _ in $(seq 1 60); do
        if docker exec --user vscode --env "SAMPLE_EXEC_AUTH=${mode}" "${name}" node /opt/codex-probe/exec-probe.mjs; then break; fi
        sleep 0.5
    done
    docker exec --user vscode --env "SAMPLE_EXEC_AUTH=${mode}" "${name}" node /opt/codex-probe/exec-probe.mjs
    docker rm -f "${name}" >/dev/null
    echo "Codex exec-server ${mode} startup, authentication, owner, environment, and restart checks passed."
done
