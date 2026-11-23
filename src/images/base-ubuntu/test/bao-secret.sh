#!/usr/bin/env bash
#
# Checks bao-secret in the image against a fake OpenBao on a bind-mounted Unix
# socket, the way the Wyrwood vault.sock reaches a container.
#
# Usage: bao-secret.sh IMAGE

set -euo pipefail

image="${1:?usage: bao-secret.sh IMAGE}"
socket_dir="$(mktemp -d)"
chmod 0755 "${socket_dir}"
python3 "$(dirname "$0")/fake-openbao.py" "${socket_dir}/vault.sock" "${socket_dir}/requests.log" &
server=$!
cleanup() {
    kill "${server}" 2>/dev/null || true
    rm -rf "${socket_dir}"
}
trap cleanup EXIT
for _ in $(seq 1 50); do
    [ -S "${socket_dir}/vault.sock" ] && break
    sleep 0.1
done

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# Runs bao-secret in the image as vscode, with BAO_ADDR pointing at the fake.
run() {
    docker run --rm --interactive --user vscode --entrypoint /usr/local/bin/bao-secret \
        --volume "${socket_dir}:/run/sample-openbao" \
        --env BAO_ADDR=unix:///run/sample-openbao/vault.sock \
        "${image}" "$@"
}

[ "$(run get secret/sample-app/token)" = sample-token-value ] || fail "get did not print the field"
[ "$(run get secret/sample-app/port)" = 8080 ] || fail "get did not print a number field"
[ "$(run get kv/sample-team/sample-service/password)" = sample-password-value ] \
    || fail "get did not read a nested path on another mount"

expect_error() {
    local expected="$1" output
    shift
    if output="$(run "$@" 2>&1)"; then
        fail "bao-secret $* succeeded"
    fi
    grep -Fq "${expected}" <<<"${output}" || fail "bao-secret $* failed for the wrong reason: ${output}"
    if grep -Fq sample-token-value <<<"${output}"; then
        fail "bao-secret $* printed a secret value in its error"
    fi
}
expect_error "field missing was not found" get secret/sample-app/missing
expect_error "is not a string, number or boolean" get secret/sample-app/nested
expect_error "permission denied for secret secret/sample-denied" get secret/sample-denied/token
expect_error "secret secret/sample-missing was not found" get secret/sample-missing/token
expect_error "not a KV version 2 secret" get secret/sample-not-kv/token
expect_error "reference must be <mount>/<path>/<field>" get secret/token
expect_error "may not be '.' or '..'" get secret/../sys/token
expect_error "usage:" get
echo "PASS: bao-secret get reads fields and reports failures without values"

answer="$(printf '%s' '{"version":"1.0","secrets":["secret/sample-app/token","secret/sample-app/enabled","secret/sample-denied/token"]}' | run vector)"
expected='{"secret/sample-app/token":{"value":"sample-token-value","error":null},"secret/sample-app/enabled":{"value":"true","error":null},"secret/sample-denied/token":{"value":null,"error":"permission denied for secret secret/sample-denied"}}'
[ "${answer}" = "${expected}" ] || fail "vector answered ${answer}"
[ "$(printf '%s' '{"version":"1.0","secrets":[]}' | run vector)" = '{}' ] || fail "vector did not answer an empty request"
if printf 'sample-not-json' | run vector >/dev/null 2>&1; then
    fail "vector accepted a request that is not JSON"
fi
echo "PASS: bao-secret vector answers Vector's exec backend protocol"

# Two fields of one secret in one Vector request read the secret once.
[ "$(grep -c 'secret/data/sample-app ' "${socket_dir}/requests.log")" -eq 5 ] \
    || fail "unexpected number of reads: $(cat "${socket_dir}/requests.log")"
if grep -q ' token$' "${socket_dir}/requests.log"; then
    fail "bao-secret sent a token"
fi
echo "PASS: bao-secret sends no token and reads each secret once per request"

if docker run --rm --user vscode --entrypoint /usr/local/bin/bao-secret --env BAO_ADDR= --env VAULT_ADDR= \
    "${image}" get secret/sample-app/token >/dev/null 2>&1; then
    fail "bao-secret succeeded without an address"
fi
echo "PASS: bao-secret fails without an address"
