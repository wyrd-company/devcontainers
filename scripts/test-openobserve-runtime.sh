#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
image="${1:-devcontainers-openobserve-runtime:test}"
name="openobserve-runtime-test-${RANDOM}-$$"

cleanup() {
    docker stop "${name}" >/dev/null 2>&1 || true
    docker rm "${name}" >/dev/null 2>&1 || true
    if [ -n "${config_container:-}" ]; then
        docker stop "${config_container}" >/dev/null 2>&1 || true
        docker rm "${config_container}" >/dev/null 2>&1 || true
    fi
    if [ -n "${config_dir:-}" ] && [ -d "${config_dir}" ]; then
        rm -rf "${config_dir}"
    fi
}
trap cleanup EXIT

docker build \
    --file "${repo_root}/test/features/openobserve/runtime.Dockerfile" \
    --tag "${image}" \
    "${repo_root}"

"${repo_root}/scripts/check-sudo-no-all.sh" "${image}"

docker run --detach \
    --name "${name}" \
    --env ZO_HTTP_ADDR=0.0.0.0 \
    --env ZO_HTTP_PORT=5180 \
    --env SAMPLE_RUNTIME_VALUE=sample-runtime-value \
    "${image}" >/dev/null

for _ in $(seq 1 60); do
    if docker exec "${name}" curl --fail --silent http://127.0.0.1:5080/ >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done
docker exec "${name}" curl --fail --silent http://127.0.0.1:5080/ >/dev/null

openobserve_pid="$(docker exec "${name}" pgrep --exact openobserve | head -n 1)"
test -n "${openobserve_pid}"
test "$(docker exec "${name}" ps -o user= -p "${openobserve_pid}" | tr -d ' ')" = vscode
docker exec --user vscode "${name}" sh -c \
    "tr '\0' '\n' </proc/${openobserve_pid}/environ | grep -qx SAMPLE_RUNTIME_VALUE=sample-runtime-value"

if docker exec "${name}" curl --fail --silent http://127.0.0.1:5180/ >/dev/null 2>&1; then
    echo "ZO_HTTP_PORT overrode the configured command-line port." >&2
    exit 1
fi

# Verify data was written to the documented default location
docker exec "${name}" test -f /home/vscode/.local/share/openobserve/db/metadata.sqlite
docker exec "${name}" bash -c '! grep -q ZO_S3_BUCKET_PREFIX /usr/local/bin/openobserve-service'

# Verify that documented bind-mounted config file is loaded and affects OpenObserve
config_container="openobserve-config-test-${RANDOM}-$$"
config_dir="$(mktemp -d)"
chmod 0777 "${config_dir}"
cat >"${config_dir}/openobserve.env" <<EOF
ZO_ROOT_USER_EMAIL=bindmount@example.com
ZO_ROOT_USER_PASSWORD=MountedSecretPass#456
EOF
chmod 0644 "${config_dir}/openobserve.env"

docker run --detach \
    --name "${config_container}" \
    --volume "${config_dir}/openobserve.env:/home/vscode/.config/openobserve/openobserve.env:ro" \
    "${image}" >/dev/null

for _ in $(seq 1 60); do
    if docker exec "${config_container}" curl --fail --silent http://127.0.0.1:5080/ >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done
docker exec "${config_container}" curl --fail --silent http://127.0.0.1:5080/ >/dev/null

config_pid="$(docker exec "${config_container}" pgrep --exact openobserve | head -n 1)"
test -n "${config_pid}"
docker exec --user vscode "${config_container}" sh -c \
    "tr '\0' '\n' </proc/${config_pid}/cmdline | grep -qx -- '-c'"
docker exec --user vscode "${config_container}" sh -c \
    "tr '\0' '\n' </proc/${config_pid}/cmdline | grep -qx -- '/home/vscode/.config/openobserve/openobserve.env'"

# Behavior-level observation: default credentials must fail, mounted credentials must succeed and return user data
if docker exec "${config_container}" curl --fail --silent \
    -u "root@example.com:Complexpass#123" http://127.0.0.1:5080/api/default/users >/dev/null 2>&1; then
    echo "Default root user credentials authenticated when custom bind-mounted config was supplied." >&2
    exit 1
fi

mounted_users="$(docker exec "${config_container}" curl --fail --silent \
    -u "bindmount@example.com:MountedSecretPass#456" http://127.0.0.1:5080/api/default/users)"
if ! printf '%s\n' "${mounted_users}" | grep -Fq '"email":"bindmount@example.com"'; then
    echo "Config file did not bootstrap root user from bind-mounted openobserve.env: ${mounted_users}." >&2
    exit 1
fi

docker stop "${config_container}" >/dev/null 2>&1 || true
docker rm "${config_container}" >/dev/null 2>&1 || true
rm -rf "${config_dir}"

assert_install_rejected() {
    local description="$1"
    local expected="$2"
    shift 2
    local output

    if output="$(docker run --rm \
        --entrypoint /bin/bash \
        --volume "${repo_root}/src/features/openobserve:/feature:ro" \
        --volume "${repo_root}/test/features/openobserve/failing-checksum-bin:/test-bin:ro" \
        "${image}" \
        -c 'env "$@" /feature/install.sh' bash "$@" 2>&1)"; then
        echo "Invalid configuration was accepted: ${description}." >&2
        exit 1
    fi
    if ! printf '%s\n' "${output}" | grep -Fq "${expected}"; then
        echo "Configuration was rejected for the wrong reason: ${description}." >&2
        printf '%s\n' "${output}" >&2
        exit 1
    fi
}

common_options=(
    VERSION=latest
    HOST=127.0.0.1
    PORT=5080
    GRPCPORT=5081
    SERVICEUSER=automatic
    DNSNAME=
    ROOTUSEREMAIL=root@example.com
    ROOTUSERPASSWORD="Complexpass#123"
    TELEMETRY=false
    SHA256=
    S3BUCKETPREFIX=
    _REMOTE_USER=vscode
)
assert_install_rejected \
    "out-of-range port" \
    "port must be an integer between 1 and 65535" \
    "${common_options[@]/PORT=5080/PORT=0}"
assert_install_rejected \
    "out-of-range grpcPort" \
    "grpcPort must be an integer between 1 and 65535" \
    "${common_options[@]/GRPCPORT=5081/GRPCPORT=0}"
assert_install_rejected \
    "port and grpcPort collision" \
    "port and grpcPort must not be the same port" \
    "${common_options[@]/GRPCPORT=5081/GRPCPORT=5080}"
assert_install_rejected \
    "invalid rootUserEmail" \
    "rootUserEmail must be a valid email address" \
    "${common_options[@]/ROOTUSEREMAIL=root@example.com/ROOTUSEREMAIL=not-an-email}"
assert_install_rejected \
    "too short rootUserPassword" \
    "rootUserPassword must be at least 8 characters long" \
    "${common_options[@]/ROOTUSERPASSWORD=Complexpass#123/ROOTUSERPASSWORD=short}"
assert_install_rejected \
    "Caddy registration on a non-loopback host" \
    "dnsName requires host" \
    VERSION=latest HOST=192.0.2.10 PORT=5080 GRPCPORT=5081 SERVICEUSER=automatic \
    DNSNAME=observe.test-container.example.test S3BUCKETPREFIX= _REMOTE_USER=vscode
assert_install_rejected \
    "Caddy registration without Caddy" \
    "dnsName requires the Caddy Feature" \
    VERSION=latest HOST=127.0.0.1 PORT=5080 GRPCPORT=5081 SERVICEUSER=automatic \
    DNSNAME=observe.test-container.example.test S3BUCKETPREFIX= _REMOTE_USER=vscode
assert_install_rejected \
    "release archive with a failed checksum" \
    "Checksum verification failed" \
    VERSION=latest HOST=127.0.0.1 PORT=5080 GRPCPORT=5081 SERVICEUSER=automatic DNSNAME= \
    SHA256=0000000000000000000000000000000000000000000000000000000000000000 S3BUCKETPREFIX= _REMOTE_USER=vscode
assert_install_rejected \
    "s3BucketPrefix with a newline" \
    "s3BucketPrefix contains unsupported characters" \
    "${common_options[@]}" S3BUCKETPREFIX=$'tools\nkanban'
assert_install_rejected \
    "s3BucketPrefix with a comma-separated list" \
    "s3BucketPrefix must be a single prefix, not a comma-separated list" \
    "${common_options[@]/S3BUCKETPREFIX=/S3BUCKETPREFIX=tools,kanban}"
assert_install_rejected \
    "s3BucketPrefix that begins with a slash" \
    "s3BucketPrefix must not begin with '/'" \
    "${common_options[@]/S3BUCKETPREFIX=/S3BUCKETPREFIX=/tools}"
assert_install_rejected \
    "s3BucketPrefix with empty path segments" \
    "s3BucketPrefix must not contain empty path segments" \
    "${common_options[@]/S3BUCKETPREFIX=/S3BUCKETPREFIX=tools//logs}"
assert_install_rejected \
    "s3BucketPrefix that is only slashes" \
    "s3BucketPrefix must not be only slashes" \
    "${common_options[@]/S3BUCKETPREFIX=/S3BUCKETPREFIX=///}"
assert_install_rejected \
    "s3BucketPrefix with an invalid character" \
    "s3BucketPrefix contains an invalid character" \
    "${common_options[@]/S3BUCKETPREFIX=/S3BUCKETPREFIX=tools prefix}"
assert_install_rejected \
    "s3BucketPrefix whose exported value would exceed 256 characters" \
    "s3BucketPrefix exceeds 256 characters" \
    "${common_options[@]/S3BUCKETPREFIX=/S3BUCKETPREFIX=$(printf 'a%.0s' {1..256})}"
assert_install_rejected \
    "s3BucketPrefix of 256 characters plus a trailing slash" \
    "s3BucketPrefix exceeds 256 characters" \
    "${common_options[@]/S3BUCKETPREFIX=/S3BUCKETPREFIX=$(printf 'a%.0s' {1..256})/}"

# Verify that passwords requiring shell quoting are preserved accurately in the service launcher
assert_password_preserved() {
    local test_pw="$1"
    local container_id
    container_id="$(docker run --detach \
        --entrypoint /bin/sh \
        --volume "${repo_root}/src/features/openobserve:/tmp/openobserve-feature:ro" \
        "${image}" -c 'sleep 300')"
    docker exec "${container_id}" env \
        VERSION=latest HOST=127.0.0.1 PORT=5080 GRPCPORT=5081 SERVICEUSER=automatic DNSNAME= \
        ROOTUSEREMAIL=root@example.com ROOTUSERPASSWORD="${test_pw}" TELEMETRY=false \
        _REMOTE_USER=vscode /tmp/openobserve-feature/install.sh >/dev/null 2>&1
    local evaluated_pw
    evaluated_pw="$(docker exec "${container_id}" bash -c '
        set +e
        HOME=/home/vscode
        eval "$(grep -E "^[[:space:]]*export ZO_ROOT_USER_PASSWORD=" /usr/local/bin/openobserve-service)"
        printf "%s" "${ZO_ROOT_USER_PASSWORD}"
    ')"
    docker stop "${container_id}" >/dev/null 2>&1 || true
    docker rm "${container_id}" >/dev/null 2>&1 || true
    if [ "${evaluated_pw}" != "${test_pw}" ]; then
        echo "Password with shell quoting was corrupted: expected '\''${test_pw}'\'', got '\''${evaluated_pw}'\''." >&2
        exit 1
    fi
}
assert_password_preserved 'correct horse battery staple'
assert_password_preserved 'P@$$w0rd with "quotes" and $symbols!'

assert_s3_bucket_prefix_exported() {
    local requested="$1"
    local expected="$2"
    local container_id
    container_id="$(docker run --detach \
        --entrypoint /bin/sh \
        --volume "${repo_root}/src/features/openobserve:/tmp/openobserve-feature:ro" \
        "${image}" -c 'sleep 300')"
    docker exec "${container_id}" env \
        VERSION=latest HOST=127.0.0.1 PORT=5080 GRPCPORT=5081 SERVICEUSER=automatic DNSNAME= \
        ROOTUSEREMAIL=root@example.com ROOTUSERPASSWORD="Complexpass#123" TELEMETRY=false \
        S3BUCKETPREFIX="${requested}" _REMOTE_USER=vscode \
        /tmp/openobserve-feature/install.sh >/dev/null 2>&1
    local evaluated
    evaluated="$(docker exec "${container_id}" bash -c '
        set +e
        eval "$(grep -E "^[[:space:]]*export ZO_S3_BUCKET_PREFIX=" /usr/local/bin/openobserve-service)"
        printf "%s" "${ZO_S3_BUCKET_PREFIX-}"
    ')"
    docker stop "${container_id}" >/dev/null 2>&1 || true
    docker rm "${container_id}" >/dev/null 2>&1 || true
    if [ "${evaluated}" != "${expected}" ]; then
        echo "s3BucketPrefix was not exported as expected: requested '${requested}', expected '${expected}', got '${evaluated}'." >&2
        exit 1
    fi
}
assert_s3_bucket_prefix_exported 'tools' 'tools/'
assert_s3_bucket_prefix_exported 'kanban/logs/' 'kanban/logs/'
max_s3_bucket_prefix_body="$(printf 'a%.0s' {1..255})"
assert_s3_bucket_prefix_exported "${max_s3_bucket_prefix_body}" "${max_s3_bucket_prefix_body}/"
assert_s3_bucket_prefix_exported "${max_s3_bucket_prefix_body}/" "${max_s3_bucket_prefix_body}/"

printf 'OpenObserve s6 runtime checks passed.\n'
