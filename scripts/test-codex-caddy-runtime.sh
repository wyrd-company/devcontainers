#!/usr/bin/env bash
# ---
# relationships:
#   verifies: codex-cli
# ---
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
base_image="${1:-$("${repo_root}/scripts/build-base-image.sh" noble)}"
native_image=devcontainers-codex-tools:test
docker build --file "${repo_root}/test/features/codex-cli/runtime.Dockerfile" --target codex-tools \
    --build-arg "BASE_IMAGE=${base_image}" --tag "${native_image}" "${repo_root}"
"${repo_root}/scripts/check-sudo-no-all.sh" "${native_image}"
names=()
cleanup() {
    for name in "${names[@]}"; do docker rm -f "${name}" >/dev/null 2>&1 || true; done
}
trap cleanup EXIT
for mode in none capability signed disabled exec-only; do
    case "${mode}" in
        none) flags=true ;;
        capability|exec-only) flags='--ws-auth capability-token --ws-token-file "/run/sample-secrets/exec token"' ;;
        signed) flags='--ws-auth signed-bearer-token --ws-shared-secret-file "/run/sample-secrets/exec key" --ws-issuer "sample issuer" --ws-audience sample-audience --ws-max-clock-skew-seconds 20' ;;
        disabled) flags=false ;;
    esac
    image="devcontainers-codex-caddy-${mode}:test"
    name="codex-caddy-runtime-${mode}-${RANDOM}-$$"
    names+=("${name}")
    start_app=true
    if [ "${mode}" = exec-only ]; then start_app=false; fi
    docker build --file "${repo_root}/test/features/codex-cli/caddy-runtime.Dockerfile" \
        --build-arg "NATIVE_IMAGE=${native_image}" --build-arg "EXECSERVER=${flags}" --build-arg "STARTAPPSERVER=${start_app}" \
        --tag "${image}" "${repo_root}"
    "${repo_root}/scripts/check-sudo-no-all.sh" "${image}"
    install_output="$(docker run --rm --entrypoint bash \
        --volume "${repo_root}/src/features/codex-cli:/feature:ro" \
        --env VERSION=latest --env "STARTAPPSERVER=${start_app}" --env "EXECSERVER=${flags}" \
        --env DNSNAME=sample-codex.example.test --env _REMOTE_USER=vscode "${image}" /feature/install.sh 2>&1)"
    if [ "${start_app}" = true ]; then
        [[ "${install_output}" == *'exposes the app-server without authentication'* ]]
    else
        [[ "${install_output}" != *'exposes the app-server without authentication'* ]]
    fi
    if [ "${mode}" = none ]; then
        [[ "${install_output}" == *'exec-server exposes unauthenticated command execution'* ]]
    else
        [[ "${install_output}" != *'exec-server exposes unauthenticated command execution'* ]]
    fi
    echo "Caddy ${mode} authentication warning assertions passed."
    profile_env=()
    if [ "${mode}" = none ]; then
        profile_env=(--env 'CODEX_HOME=/home/vscode/sample profile, "quoted"')
    fi
    docker run --detach --name "${name}" --add-host sample-codex.example.test:127.0.0.1 \
        --env SAMPLE_RUNTIME_VALUE=sample-runtime-value "${profile_env[@]}" "${image}" >/dev/null
    if [ "${mode}" = none ]; then
        docker exec "${name}" install -d -m 0700 -o vscode -g vscode '/home/vscode/sample profile, "quoted"'
    fi
    for _ in $(seq 1 60); do
        if docker exec "${name}" curl -ksS -o /dev/null https://sample-codex.example.test; then break; fi
        sleep 0.5
    done
    docker exec "${name}" curl -ksS -o /dev/null https://sample-codex.example.test
    docker exec "${name}" cp /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt /opt/codex-probe/sample-ca.crt
    docker exec "${name}" chmod 0644 /opt/codex-probe/sample-ca.crt
    docker cp "${repo_root}/test/features/codex-cli/probe.mjs" "${name}:/opt/codex-probe/probe.mjs"
    if [ "${start_app}" = true ]; then
    docker exec --user vscode --env SAMPLE_APP_ENDPOINT=wss://sample-codex.example.test/ \
        --env SAMPLE_CA_FILE=/opt/codex-probe/sample-ca.crt "${name}" node /opt/codex-probe/probe.mjs
    test "$(docker exec "${name}" curl --cacert /opt/codex-probe/sample-ca.crt -sS -o /dev/null -w '%{http_code}' -H 'Origin: https://sample-origin.example.test' https://sample-codex.example.test/)" = 403
    else
        test "$(docker exec "${name}" curl --cacert /opt/codex-probe/sample-ca.crt -sS -o /dev/null -w '%{http_code}' https://sample-codex.example.test/)" = 404
        docker exec "${name}" test ! -e /etc/s6-overlay/user-bundles.d/user/contents.d/codex-cli
    fi
    if [ "${mode}" = disabled ]; then
        test "$(docker exec "${name}" curl --cacert /opt/codex-probe/sample-ca.crt -sS -o /dev/null -w '%{http_code}' https://sample-codex.example.test/exec-server)" = 404
    else
        auth_mode="${mode}"
        if [ "${mode}" = exec-only ]; then auth_mode=capability; fi
        docker exec --user vscode --env SAMPLE_EXEC_ENDPOINT=wss://sample-codex.example.test/exec-server \
            --env "SAMPLE_EXEC_AUTH=${auth_mode}" --env SAMPLE_CA_FILE=/opt/codex-probe/sample-ca.crt "${name}" node /opt/codex-probe/exec-probe.mjs
    fi
    if [ "${start_app}" = true ]; then
    pid="$(docker exec "${name}" pgrep -f '^socat TCP4-LISTEN:4500,bind=127.0.0.1,reuseaddr,fork' | head -n 1)"
    test -n "${pid}"
    test "$(docker exec "${name}" ps -o user= -p "${pid}" | tr -d ' ')" = vscode
    for expected in HOME=/home/vscode USER=vscode SAMPLE_RUNTIME_VALUE=sample-runtime-value; do
        docker exec --user vscode "${name}" sh -c 'tr "\0" "\n" <"/proc/$1/environ" | grep -Fxq "$2"' sh "${pid}" "${expected}"
    done
    docker exec "${name}" /command/s6-svc -r /run/service/codex-cli
    for _ in $(seq 1 60); do
        if docker exec --user vscode --env SAMPLE_APP_ENDPOINT=wss://sample-codex.example.test/ \
            --env SAMPLE_CA_FILE=/opt/codex-probe/sample-ca.crt "${name}" node /opt/codex-probe/probe.mjs; then break; fi
        sleep 0.5
    done
    docker exec --user vscode --env SAMPLE_APP_ENDPOINT=wss://sample-codex.example.test/ \
        --env SAMPLE_CA_FILE=/opt/codex-probe/sample-ca.crt "${name}" node /opt/codex-probe/probe.mjs
    fi
    docker rm -f "${name}" >/dev/null
    echo "Codex Caddy ${mode} routes, authentication, shared Unix server, Origin policy, and restart passed."
done
