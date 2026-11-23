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
expect_error "did not return a KV version 2 secret" get secret/sample-not-kv/token
expect_error "did not return a KV version 2 secret" get secret/sample-empty/token
expect_error "did not return a KV version 2 secret" get secret/sample-twice/token
expect_error "reference must be <mount>/<path>/<field>" get secret/token
expect_error "may not be '.' or '..'" get secret/../sys/token
expect_error "usage:" get
reads_before="$(wc -l <"${socket_dir}/requests.log")"
expect_error "reference must be <mount>/<path>/<field>" get $'secret/sample-app/token\ninvalid'
expect_error "reference must be <mount>/<path>/<field>" get $'secret/sample-app/token\n'
[ "$(wc -l <"${socket_dir}/requests.log")" -eq "${reads_before}" ] || fail "a reference with a newline reached OpenBao"
echo "PASS: bao-secret get reads fields and reports failures without values"

answer="$(printf '%s' '{"version":"1.0","secrets":["secret/sample-app/token","secret/sample-app/enabled","secret/sample-denied/token"]}' | run vector)"
expected='{"secret/sample-app/token":{"value":"sample-token-value","error":null},"secret/sample-app/enabled":{"value":"true","error":null},"secret/sample-denied/token":{"value":null,"error":"permission denied for secret secret/sample-denied"}}'
[ "${answer}" = "${expected}" ] || fail "vector answered ${answer}"
reads_before="$(wc -l <"${socket_dir}/requests.log")"
answer="$(printf '%s' '{"version":"1.0","secrets":["secret/sample-app/token\ninvalid","secret/sample-empty/token"]}' | run vector)"
jq --exit-status '
    (keys == ["secret/sample-app/token\ninvalid", "secret/sample-empty/token"])
    and (.["secret/sample-app/token\ninvalid"] | .value == null and (.error | test("<mount>/<path>/<field>")))
    and (.["secret/sample-empty/token"] | .value == null and (.error | test("did not return a KV version 2 secret")))
' <<<"${answer}" >/dev/null || fail "vector mishandled a key with a newline or an empty response: ${answer}"
[ "$(wc -l <"${socket_dir}/requests.log")" -eq $((reads_before + 1)) ] \
    || fail "a key with a newline reached OpenBao: $(tail -n 3 "${socket_dir}/requests.log")"
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

# Address errors are found before curl runs and never repeat the address.
address_error() {
    local address="$1" expected="$2" output
    if output="$(docker run --rm --user vscode --entrypoint /usr/local/bin/bao-secret --env "BAO_ADDR=${address}" \
        "${image}" get secret/sample-app/token 2>&1)"; then
        fail "bao-secret accepted the address ${address}"
    fi
    grep -Fq "${expected}" <<<"${output}" || fail "the address ${address} was refused for the wrong reason: ${output}"
    if grep -Fq sample-address-password <<<"${output}"; then
        fail "an address error repeated the address: ${output}"
    fi
}
address_error 'http://[' 'must be scheme://host[:port]'
address_error 'http://sample:sample-address-password@sample.example.test' 'must be scheme://host[:port]'
address_error 'sample.example.test:8200' 'must start with unix://, http:// or https://'
address_error 'unix://relative.sock' 'must name an absolute socket path'
address_error 'unix:///run/sample-missing.sock' 'could not reach OpenBao (curl exit status 7)'
echo "PASS: address errors are reported before curl runs and do not repeat the address"

# An inherited environment cannot leak a value. A .curlrc that writes the
# response to a file and adds a token header, exported variables with the
# helper's names, xtrace through SHELLOPTS and BASH_ENV, and exported
# functions named jq, curl, set, unset, builtin and printf are all in place, and spies in front of the real curl and jq record every child's
# command line and environment.
hostile="$(docker run --rm --interactive --user vscode --entrypoint /bin/bash \
    --volume "${socket_dir}:/run/sample-openbao" \
    --env BAO_ADDR=unix:///run/sample-openbao/vault.sock \
    "${image}" -s <<'EOS'
set -u
mkdir -p /tmp/sample-spy
for tool in curl jq; do
    real="$(command -v "${tool}")"
    printf '#!/bin/sh\n{ echo "ARGV %s $*"; env; } >>/tmp/sample-spy/log\nexec %s "$@"\n' "${tool}" "${real}" \
        >"/tmp/sample-spy/${tool}"
    chmod 0755 "/tmp/sample-spy/${tool}"
done
printf 'set -o xtrace\n: >/tmp/sample-bash-env-ran\n' >/tmp/sample-bash-env
printf 'output = "/tmp/sample-curlrc-output"\nheader = "X-Vault-Token: sample-curlrc-token"\n' >"${HOME}/.curlrc"
run_hostile() {
    env PATH="/tmp/sample-spy:${PATH}" SHELLOPTS=xtrace BASHOPTS=xpg_echo BASH_ENV=/tmp/sample-bash-env \
        body=sample-inherited result=sample-inherited error=sample-inherited response=sample-inherited \
        "BASH_FUNC_jq%%=() { cat >/tmp/sample-function-output; }" \
        "BASH_FUNC_curl%%=() { cat >/tmp/sample-function-output; }" \
        "BASH_FUNC_set%%=() { :; }" "BASH_FUNC_unset%%=() { :; }" "BASH_FUNC_builtin%%=() { :; }" \
        "BASH_FUNC_printf%%=() { builtin printf \"\$@\"; builtin printf \"\$@\" >>/tmp/sample-function-output; }" \
        /usr/local/bin/bao-secret "$@"
}
echo "get=$(run_hostile get secret/sample-app/token 2>/tmp/sample-spy/stderr)"
echo "vector=$(printf '%s' '{"version":"1.0","secrets":["secret/sample-app/token"]}' | run_hostile vector 2>>/tmp/sample-spy/stderr)"
[ ! -e /tmp/sample-bash-env-ran ] || echo "LEAK: BASH_ENV was sourced"
for leak in /tmp/sample-curlrc-output /tmp/sample-function-output; do
    [ ! -e "${leak}" ] || echo "LEAK: ${leak} exists"
done
grep -l sample-token-value /tmp/sample-spy/stderr >/dev/null && echo "LEAK: stderr holds the value"
grep -n sample-token-value /tmp/sample-spy/log >/dev/null && echo "LEAK: a child's command line or environment holds the value"
grep -q '^body=' /tmp/sample-spy/log && echo "LEAK: an inherited body variable reached a child"
echo "spied=$(grep -c '^ARGV ' /tmp/sample-spy/log)"
EOS
)"
grep -qx 'get=sample-token-value' <<<"${hostile}" || fail "bao-secret get did not work in a hostile environment: ${hostile}"
grep -qx 'vector={"secret/sample-app/token":{"value":"sample-token-value","error":null}}' <<<"${hostile}" \
    || fail "bao-secret vector did not work in a hostile environment: ${hostile}"
if grep -q '^LEAK' <<<"${hostile}"; then
    fail "an inherited environment leaked a value: $(grep '^LEAK' <<<"${hostile}")"
fi
spied="$(sed -n 's/^spied=//p' <<<"${hostile}")"
[ "${spied:-0}" -ge 6 ] || fail "the curl and jq spies did not run: ${hostile}"
if grep -q ' token$' "${socket_dir}/requests.log"; then
    fail "a .curlrc header reached OpenBao"
fi
echo "PASS: no value leaks through .curlrc, exported variables, xtrace, BASH_ENV or exported functions (${spied} children spied)"
