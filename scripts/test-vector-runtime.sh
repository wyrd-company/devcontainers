#!/usr/bin/env bash
#
# Runtime acceptance for the Vector Feature under s6-overlay.
#
# Usage: test-vector-runtime.sh [image-tag]
#
# SERVICE_USER, WATCH_CONFIG_METHOD and WATCH_CONFIG_POLL_INTERVAL_SECONDS
# select the Feature options. A host whose user has run out of inotify
# instances can run the hot-reload checks with WATCH_CONFIG_METHOD=poll.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
base_image="${BASE_IMAGE:-$("${repo_root}/scripts/build-base-image.sh" noble)}"
image="${1:-devcontainers-vector-runtime:test}"
service_user_option="${SERVICE_USER:-automatic}"
watch_method="${WATCH_CONFIG_METHOD:-recommended}"
poll_interval="${WATCH_CONFIG_POLL_INTERVAL_SECONDS:-30}"
name="vector-runtime-test-${RANDOM}-$$"

expected_user=vscode
if [ "${service_user_option}" != automatic ]; then
    expected_user="${service_user_option}"
fi

cleanup() {
    docker stop "${name}" >/dev/null 2>&1 || true
    docker rm "${name}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    docker logs "${name}" 2>&1 | tail -n 40 >&2 || true
    exit 1
}

pass() {
    echo "PASS: $*"
}

# Waits up to 60 seconds for a command in the container to succeed.
wait_for() {
    local description="$1"
    shift
    for _ in $(seq 1 120); do
        if docker exec "${name}" "$@" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.5
    done
    fail "timed out waiting for ${description}"
}

vector_pid() {
    docker exec "${name}" pgrep --exact vector | head -n 1 || true
}

as_user() {
    docker exec --user "${expected_user}" "${name}" bash -c "$1"
}

# Writes a pipeline file the way an editor or agent should: to a name Vector
# ignores, then renamed into place.
write_pipeline() {
    local file="$1" content="$2"
    printf '%s\n' "${content}" | docker exec -i --user "${expected_user}" "${name}" \
        bash -c "cat >/etc/vector/conf.d/.${file}.tmp && mv /etc/vector/conf.d/.${file}.tmp /etc/vector/conf.d/${file}"
}

reload_count() {
    docker logs "${name}" 2>&1 | grep -c 'Vector has reloaded' || true
}

wait_for_reload() {
    local before="$1" description="$2"
    for _ in $(seq 1 $((poll_interval * 2 + 60))); do
        if [ "$(reload_count)" -gt "${before}" ]; then
            return 0
        fi
        sleep 0.5
    done
    fail "timed out waiting for Vector to reload after ${description}"
}

captured() {
    docker exec "${name}" sh -c 'cat /tmp/sample-capture.jsonl 2>/dev/null || true'
}

docker build \
    --file "${repo_root}/test/features/vector/runtime.Dockerfile" \
    --build-arg "BASE_IMAGE=${base_image}" \
    --build-arg "SERVICE_USER=${service_user_option}" \
    --build-arg "WATCH_CONFIG_METHOD=${watch_method}" \
    --build-arg "WATCH_CONFIG_POLL_INTERVAL_SECONDS=${poll_interval}" \
    --tag "${image}" \
    "${repo_root}"

"${repo_root}/scripts/check-sudo-no-all.sh" "${image}"

# The VECTOR_* values would point Vector elsewhere if they overrode the flags.
docker run --detach \
    --name "${name}" \
    --env SAMPLE_RUNTIME_VALUE=sample-runtime-value \
    --env VECTOR_CONFIG=/tmp/sample-env-config.yaml \
    --env VECTOR_CONFIG_DIR=/tmp/sample-env-config.d \
    --env VECTOR_CONFIG_YAML=/tmp/sample-env-extra.yaml \
    --env VECTOR_WATCH_CONFIG_METHOD=sample-invalid-method \
    "${image}" >/dev/null

wait_for "the Vector API" bash -c 'exec 3<>/dev/tcp/127.0.0.1/8686'
pid="$(vector_pid)"
[ -n "${pid}" ] || fail "Vector is not running"

owner="$(docker exec "${name}" ps -o user= -p "${pid}" | tr -d ' ')"
[ "${owner}" = "${expected_user}" ] || fail "Vector runs as ${owner}, expected ${expected_user}"
pass "Vector runs as ${expected_user}"

docker exec --user "${expected_user}" "${name}" sh -c "tr '\0' '\n' </proc/${pid}/environ" >/tmp/"${name}".environ
grep -qx SAMPLE_RUNTIME_VALUE=sample-runtime-value /tmp/"${name}".environ \
    || fail "Vector did not receive the container environment"
expected_home="$(docker exec "${name}" getent passwd "${expected_user}" | cut -d: -f6)"
grep -qx "HOME=${expected_home}" /tmp/"${name}".environ || fail "Vector did not receive HOME=${expected_home}"
grep -qx "USER=${expected_user}" /tmp/"${name}".environ || fail "Vector did not receive USER=${expected_user}"
if grep -q '^VECTOR_\(CONFIG\|WATCH_CONFIG\)' /tmp/"${name}".environ; then
    fail "a managed VECTOR_* setting reached Vector"
fi
rm -f /tmp/"${name}".environ
pass "Vector runs with the user's environment"

docker logs "${name}" 2>&1 \
    | grep -F 'Loading configs. paths=["/etc/vector/vector.yaml", "/etc/vector/conf.d"]' >/dev/null \
    || fail "Vector loaded configuration other than the managed paths"
cmdline="$(docker exec "${name}" sh -c "tr '\0' ' ' </proc/${pid}/cmdline")"
case "${cmdline}" in
    *"--watch-config-method ${watch_method} "*) ;;
    *) fail "Vector command line does not select ${watch_method}: ${cmdline}" ;;
esac
pass "environment variables do not override the managed flags"

# The token reaches the pipeline from the OpenBao secret file convention.
docker exec "${name}" sh -c \
    'install -d -m 0755 /run/openbao/secrets && printf "SAMPLE_WEBHOOK_TOKEN=sample-webhook-token\n" >/run/openbao/secrets/vector.env && chmod 0644 /run/openbao/secrets/vector.env'
previous_pid="${pid}"
docker exec "${name}" /command/s6-svc -r /run/service/vector
for _ in $(seq 1 60); do
    pid="$(vector_pid)"
    if [ -n "${pid}" ] && [ "${pid}" != "${previous_pid}" ]; then
        break
    fi
    sleep 0.5
done
[ -n "${pid}" ] && [ "${pid}" != "${previous_pid}" ] || fail "s6 did not restart Vector"
wait_for "the Vector API after restart" bash -c 'exec 3<>/dev/tcp/127.0.0.1/8686'
pass "s6 restarts Vector"

as_user 'install -d /tmp/sample-board && : >/tmp/sample-board/activity.jsonl'

capture_pipeline='sources:
  sample_capture_in:
    type: http_server
    address: 127.0.0.1:18080
    path: /api/v1/webhooks/sample-dag
    headers: [Authorization]
    decoding: {codec: bytes}
    framing: {method: bytes}
sinks:
  sample_capture_out:
    type: file
    inputs: [sample_capture_in]
    path: /tmp/sample-capture.jsonl
    encoding: {codec: json}'

board_pipeline='sources:
  sample_board_activity:
    type: file
    include: [/tmp/sample-board/activity.jsonl]
transforms:
  sample_board_payload:
    type: remap
    inputs: [sample_board_activity]
    source: |
      . = {"payload": parse_json!(string!(.message))}
sinks:
  sample_board_webhook:
    type: http
    inputs: [sample_board_payload]
    uri: http://127.0.0.1:18080/api/v1/webhooks/sample-dag
    auth:
      strategy: bearer
      token: "SECRET[environment.SAMPLE_WEBHOOK_TOKEN]"
    encoding: {codec: json}
    framing: {method: newline_delimited}
    batch: {max_events: 1}'

before="$(reload_count)"
write_pipeline sample-capture.yaml "${capture_pipeline}"
wait_for_reload "${before}" "adding a pipeline"
wait_for "the capture pipeline" bash -c 'exec 3<>/dev/tcp/127.0.0.1/18080'
before="$(reload_count)"
write_pipeline sample-board.yaml "${board_pipeline}"
wait_for_reload "${before}" "adding a second pipeline"
pass "added pipeline files are loaded without a restart"

validation="$(as_user 'vector-service validate' 2>&1)" \
    || fail "vector-service validate rejected valid pipelines: ${validation}"
grep -q Validated <<<"${validation}" || fail "vector-service validate did not report success: ${validation}"
pass "vector-service validate accepts the pipelines"

as_user 'printf "%s\n" "{\"action\":\"move\",\"task_id\":1}" >>/tmp/sample-board/activity.jsonl'
wait_for "the first event" grep -q 'move' /tmp/sample-capture.jsonl
captured | grep -F '"Authorization":"Bearer sample-webhook-token"' >/dev/null \
    || fail "the webhook did not receive the token from the secret file"
captured | grep -F '"message":"{\"payload\":{\"action\":\"move\",\"task_id\":1}}' >/dev/null \
    || fail "the webhook did not receive the event payload"
pass "a JSONL line is delivered to the webhook with the secret token"

# A broken file is rejected, and the running pipelines keep working.
broken_pipeline='sinks:
  sample_broken:
    type: sample-not-a-sink
    inputs: [sample_board_payload]'
write_pipeline sample-broken.yaml "${broken_pipeline}"
for _ in $(seq 1 $((poll_interval * 2 + 60))); do
    if docker logs "${name}" 2>&1 | grep -q 'reload aborted'; then
        break
    fi
    sleep 0.5
done
docker logs "${name}" 2>&1 | grep -q 'reload aborted' || fail "Vector did not reject the broken file"
if as_user 'vector-service validate' >/dev/null 2>&1; then
    fail "vector-service validate accepted a broken pipeline"
fi
as_user 'printf "%s\n" "{\"action\":\"edit\",\"task_id\":2}" >>/tmp/sample-board/activity.jsonl'
wait_for "an event after the rejected reload" grep -q 'edit' /tmp/sample-capture.jsonl
pass "a broken file is rejected and the active pipelines keep running"

before="$(reload_count)"
as_user 'rm /etc/vector/conf.d/sample-broken.yaml'
wait_for_reload "${before}" "removing the broken file"

before="$(reload_count)"
as_user 'rm /etc/vector/conf.d/sample-board.yaml'
wait_for_reload "${before}" "removing a pipeline"
as_user 'printf "%s\n" "{\"action\":\"block\",\"task_id\":3}" >>/tmp/sample-board/activity.jsonl'
sleep 5
if captured | grep -q 'block'; then
    fail "a removed pipeline still delivered events"
fi
pass "removed pipeline files are unloaded"

before="$(reload_count)"
write_pipeline sample-board.yaml "${board_pipeline}"
wait_for_reload "${before}" "restoring a pipeline"
wait_for "the event written while the pipeline was unloaded" grep -q 'block' /tmp/sample-capture.jsonl
pass "a restored pipeline resumes from its checkpoint"

[ "$(vector_pid)" = "${pid}" ] || fail "Vector restarted during hot reloads"
pass "every reload happened in the same Vector process"

assert_install_rejected() {
    local description="$1" expected="$2" output
    shift 2
    if output="$(docker run --rm \
        --entrypoint /bin/bash \
        --volume "${repo_root}/src/features/vector:/feature:ro" \
        "${image}" \
        -c 'env "$@" /feature/install.sh' bash \
        VERSION=latest SERVICEUSER=automatic APIADDRESS=127.0.0.1:8686 \
        WATCHCONFIGMETHOD=recommended WATCHCONFIGPOLLINTERVALSECONDS=30 _REMOTE_USER=vscode \
        "$@" 2>&1)"; then
        fail "invalid configuration was accepted: ${description}"
    fi
    grep -Fq "${expected}" <<<"${output}" \
        || fail "configuration was rejected for the wrong reason: ${description}: ${output}"
}

assert_install_rejected "a version that is not semantic" "version must be 'latest'" 'VERSION=0.61'
assert_install_rejected "a version with shell syntax" "version must be 'latest'" 'VERSION=0.61.0;false'
assert_install_rejected "a missing service user" "does not exist" 'SERVICEUSER=sample-missing-user'
assert_install_rejected "an API address without a port" "must be host:port" 'APIADDRESS=127.0.0.1'
assert_install_rejected "an API host name" "must use an IP address" 'APIADDRESS=sample.example.test:8686'
assert_install_rejected "an API address with a newline" "must use an IP address" $'APIADDRESS=127.0.0.1\n:8686'
assert_install_rejected "an API address with braces" "must use an IP address" 'APIADDRESS={127.0.0.1}:8686'
assert_install_rejected "an API port out of range" "port from 1 to 65535" 'APIADDRESS=127.0.0.1:70000'
assert_install_rejected "an unknown watch method" "watchConfigMethod must be" 'WATCHCONFIGMETHOD=sample-method'
assert_install_rejected "a zero poll interval" "watchConfigPollIntervalSeconds must be" 'WATCHCONFIGPOLLINTERVALSECONDS=0'
assert_install_rejected "a poll interval with shell syntax" "watchConfigPollIntervalSeconds must be" 'WATCHCONFIGPOLLINTERVALSECONDS=5;false'
pass "invalid options are rejected before installation"

printf 'Vector s6 runtime checks passed.\n'
