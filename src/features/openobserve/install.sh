#!/usr/bin/env bash

set -euo pipefail

log() {
    echo "[openobserve] $*"
}

err() {
    echo "[openobserve] ERROR: $*" >&2
    exit 1
}

pick_service_user() {
    local requested="${1:-automatic}"
    local candidate

    if [ -n "${requested}" ] && [ "${requested}" != automatic ] && [ "${requested}" != auto ]; then
        id -u "${requested}" >/dev/null 2>&1 || err "Requested service user '${requested}' does not exist."
        echo "${requested}"
        return
    fi

    for candidate in "${_REMOTE_USER:-}" "${_CONTAINER_USER:-}" vscode root; do
        if [ -n "${candidate}" ] && id -u "${candidate}" >/dev/null 2>&1; then
            echo "${candidate}"
            return
        fi
    done

    err "Unable to resolve a service user."
}

resolve_latest_version() {
    local releases_json tag
    if releases_json="$(curl --fail --location --silent --show-error --retry 3 \
        ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
        -H "Accept: application/vnd.github+json" \
        https://api.github.com/repos/openobserve/openobserve/releases 2>/dev/null)"; then
        if command -v jq >/dev/null 2>&1; then
            tag="$(printf '%s\n' "${releases_json}" | jq -r '[.[] | select(.draft == false and .prerelease == false and (.tag_name | contains("-rc") | not))] | first | .tag_name // empty' 2>/dev/null || true)"
        else
            tag="$(printf '%s\n' "${releases_json}" | grep -B 2 -A 5 '"prerelease": false' | grep -B 5 -A 2 '"draft": false' | grep -oE '"tag_name": *"[^"]+"' | cut -d'"' -f4 | grep -v -- '-rc' | head -n 1 || true)"
        fi
        if [ -n "${tag}" ] && [ "${tag}" != "null" ]; then
            echo "${tag}"
            return
        fi
    fi
    # Fallback to current known stable release if GitHub API is unreachable or rate limited
    echo "v0.92.2"
}

[ "$(id -u)" -eq 0 ] || err "This Feature must run as root."
[ -r /etc/os-release ] || err "Unable to detect Linux distribution."
requested_version="${VERSION:-latest}"
PORT="${PORT:-5080}"
GRPCPORT="${GRPCPORT:-5081}"
HOST="${HOST:-127.0.0.1}"
SERVICEUSER="${SERVICEUSER:-automatic}"
DNSNAME="${DNSNAME:-}"
ROOTUSEREMAIL="${ROOTUSEREMAIL:-root@example.com}"
ROOTUSERPASSWORD="${ROOTUSERPASSWORD:-Complexpass#123}"
TELEMETRY="${TELEMETRY:-false}"
SHA256="${SHA256:-}"
S3BUCKETPREFIX="${S3BUCKETPREFIX:-}"

# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-} ${ID_LIKE:-}" in
    *debian*|*ubuntu*) ;;
    *) err "This Feature currently supports Debian/Ubuntu-based images." ;;
esac

for required_path in /init /command/s6-rc /etc/s6-overlay/s6-rc.d /etc/s6-overlay/user-bundles.d/user/contents.d; do
    [ -e "${required_path}" ] || err "This Feature requires an s6-overlay 3 image with /init as PID 1."
done

[[ "${PORT}" =~ ^[0-9]+$ ]] || err "port must be an integer between 1 and 65535."
[ "${#PORT}" -le 5 ] || err "port must be an integer between 1 and 65535."
((10#${PORT} >= 1 && 10#${PORT} <= 65535)) || err "port must be an integer between 1 and 65535."

[[ "${GRPCPORT}" =~ ^[0-9]+$ ]] || err "grpcPort must be an integer between 1 and 65535."
[ "${#GRPCPORT}" -le 5 ] || err "grpcPort must be an integer between 1 and 65535."
((10#${GRPCPORT} >= 1 && 10#${GRPCPORT} <= 65535)) || err "grpcPort must be an integer between 1 and 65535."

[ "${PORT}" != "${GRPCPORT}" ] || err "port and grpcPort must not be the same port."

[[ "${ROOTUSEREMAIL}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] \
    || err "rootUserEmail must be a valid email address."

[ "${#ROOTUSERPASSWORD}" -ge 8 ] || err "rootUserPassword must be at least 8 characters long."

case "${TELEMETRY}" in
    true|false) ;;
    *) err "telemetry must be 'true' or 'false'." ;;
esac

if [ -n "${SHA256}" ]; then
    [[ "${SHA256}" =~ ^[0-9a-fA-F]{64}$ ]] \
        || err "sha256 must be a 64-character hexadecimal SHA256 hash."
fi

normalized_s3_bucket_prefix=""
if [ -n "${S3BUCKETPREFIX}" ]; then
    case "${S3BUCKETPREFIX}" in
        *$'\n'*|*$'\r'*) err "s3BucketPrefix contains unsupported characters." ;;
        *,*) err "s3BucketPrefix must be a single prefix, not a comma-separated list." ;;
    esac
    normalized_s3_bucket_prefix="${S3BUCKETPREFIX}"
    while [ "${normalized_s3_bucket_prefix}" != "${normalized_s3_bucket_prefix%/}" ]; do
        normalized_s3_bucket_prefix="${normalized_s3_bucket_prefix%/}"
    done
    [ -n "${normalized_s3_bucket_prefix}" ] || err "s3BucketPrefix must not be only slashes."
    case "${normalized_s3_bucket_prefix}" in
        /*) err "s3BucketPrefix must not begin with '/'." ;;
        *//*) err "s3BucketPrefix must not contain empty path segments." ;;
    esac
    [[ "${normalized_s3_bucket_prefix}" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] \
        || err "s3BucketPrefix contains an invalid character."
    # Cap the exported value (one trailing slash). Trailing slashes on input are stripped first.
    normalized_s3_bucket_prefix="${normalized_s3_bucket_prefix}/"
    [ "${#normalized_s3_bucket_prefix}" -le 256 ] || err "s3BucketPrefix exceeds 256 characters."
fi

normalized_host="${HOST}"
if [ "${normalized_host}" = localhost ]; then
    normalized_host=127.0.0.1
fi
[ -n "${normalized_host}" ] || err "host must not be empty."
case "${normalized_host}" in
    *$'\n'*|*$'\r'*) err "host contains unsupported characters." ;;
esac

if [ -n "${DNSNAME}" ]; then
    [ "${#DNSNAME}" -le 253 ] || err "dnsName exceeds the 253-character DNS limit."
    IFS=. read -r -a dns_labels <<<"${DNSNAME}"
    [ "${#dns_labels[@]}" -ge 2 ] || err "dnsName must be a fully qualified DNS name."
    for label in "${dns_labels[@]}"; do
        [[ "${label}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] \
            || err "dnsName contains an invalid DNS label: '${label}'."
    done
    case "${normalized_host}" in
        127.0.0.1|0.0.0.0) ;;
        *) err "dnsName requires host to be '127.0.0.1', 'localhost', or '0.0.0.0'." ;;
    esac
    [ -d /etc/caddy/conf.d ] \
        || err "dnsName requires the Caddy Feature and its /etc/caddy/conf.d directory."
    [ -d /etc/caddy/required-hosts.d ] \
        || err "dnsName requires a Caddy Feature version with DNS readiness support."
fi

case "$(uname -m)" in
    x86_64|amd64) architecture=amd64 ;;
    arm64|aarch64) architecture=arm64 ;;
    *) err "Unsupported architecture: $(uname -m)." ;;
esac

service_user="$(pick_service_user "${SERVICEUSER}")"
service_home="$(getent passwd "${service_user}" | cut -d: -f6)"
[ -n "${service_home}" ] || err "Unable to resolve the home directory for ${service_user}."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends ca-certificates curl jq

download_dir="$(mktemp -d)"
trap 'rm -rf "${download_dir}"' EXIT

if [ "${requested_version}" = latest ]; then
    log "Resolving latest stable OpenObserve release..."
    resolved_version="$(resolve_latest_version)"
    log "Resolved latest version to ${resolved_version}"
    normalized_version="${resolved_version#v}"
else
    [[ "${requested_version}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]] \
        || err "version must be 'latest' or a semantic version such as '0.92.2'."
    normalized_version="${requested_version#v}"
fi

archive_name="openobserve-v${normalized_version}-linux-${architecture}.tar.gz"
release_url="https://downloads.openobserve.ai/releases/openobserve/v${normalized_version}"
archive="${download_dir}/${archive_name}"

log "Downloading OpenObserve ${normalized_version} for ${architecture} from ${release_url}/${archive_name}"
curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
    --output "${archive}" "${release_url}/${archive_name}"

if [ -n "${SHA256}" ]; then
    printf '%s  %s\n' "${SHA256}" "${archive}" | sha256sum --check --status \
        || err "Checksum verification failed for ${archive_name}."
    log "Verified checksum for ${archive_name}."
else
    checksums_file="${download_dir}/checksums.txt"
    if curl --fail --location --silent --show-error --retry 2 \
        --output "${checksums_file}" "${release_url}/checksums.txt" 2>/dev/null; then
        expected_checksum="$(awk -v archive="${archive_name}" '$2 == archive { print $1 }' "${checksums_file}")"
        if [[ "${expected_checksum}" =~ ^[0-9a-fA-F]{64}$ ]]; then
            printf '%s  %s\n' "${expected_checksum}" "${archive}" | sha256sum --check --status \
                || err "Checksum verification failed for ${archive_name}."
            log "Verified checksum from upstream checksums.txt for ${archive_name}."
        fi
    else
        log "Upstream does not publish machine-readable checksums for OSS releases; skipping checksum verification (use 'sha256' option to pin)."
    fi
fi

extract_dir="${download_dir}/extract"
install -d -m 0755 "${extract_dir}"
tar -xzf "${archive}" -C "${extract_dir}"
[ -x "${extract_dir}/openobserve" ] || err "The OpenObserve release did not contain an executable named openobserve."
install -m 0755 "${extract_dir}/openobserve" /usr/local/bin/openobserve

printf -v quoted_openobserve '%q' /usr/local/bin/openobserve
printf -v quoted_host '%q' "${normalized_host}"
printf -v quoted_port '%q' "${PORT}"
printf -v quoted_grpc_port '%q' "${GRPCPORT}"
printf -v quoted_default_email '%q' "${ROOTUSEREMAIL}"
printf -v quoted_default_password '%q' "${ROOTUSERPASSWORD}"
printf -v quoted_default_telemetry '%q' "${TELEMETRY}"
printf -v quoted_public_url '%q' "https://${DNSNAME}"
printf -v quoted_s3_bucket_prefix '%q' "${normalized_s3_bucket_prefix}"

cat >/usr/local/bin/openobserve-service <<EOF
#!/usr/bin/env bash
set -euo pipefail

service_home="\${HOME:-}"
if [ -z "\${service_home}" ]; then
    service_home="\$(getent passwd "\$(id -un)" | cut -d: -f6)"
fi

if [ -z "\${ZO_DATA_DIR:-}" ]; then
    export ZO_DATA_DIR="\${service_home}/.local/share/openobserve"
fi
if [ -z "\${ZO_ROOT_USER_EMAIL:-}" ]; then
    export ZO_ROOT_USER_EMAIL=${quoted_default_email}
fi
if [ -z "\${ZO_ROOT_USER_PASSWORD:-}" ]; then
    export ZO_ROOT_USER_PASSWORD=${quoted_default_password}
fi
if [ -z "\${ZO_TELEMETRY:-}" ]; then
    export ZO_TELEMETRY=${quoted_default_telemetry}
fi
EOF

if [ -n "${DNSNAME}" ]; then
    cat >>/usr/local/bin/openobserve-service <<EOF
export ZO_WEB_URL=${quoted_public_url}
EOF
fi

if [ -n "${normalized_s3_bucket_prefix}" ]; then
    cat >>/usr/local/bin/openobserve-service <<EOF
export ZO_S3_BUCKET_PREFIX=${quoted_s3_bucket_prefix}
EOF
fi

cat >>/usr/local/bin/openobserve-service <<EOF

# Pinned host and ports take precedence over container environment overrides
export ZO_HTTP_ADDR=${quoted_host}
export ZO_HTTP_PORT=${quoted_port}
export ZO_GRPC_PORT=${quoted_grpc_port}

config_args=()
default_config="\${service_home}/.config/openobserve/openobserve.env"
config_file="\${OPENOBSERVE_CONFIG_FILE:-\${default_config}}"
if [ -f "\${config_file}" ]; then
    config_args+=("-c" "\${config_file}")
fi

exec ${quoted_openobserve} "\${config_args[@]}" "\$@"
EOF
chmod 0755 /usr/local/bin/openobserve-service

service_dir=/etc/s6-overlay/s6-rc.d/openobserve
install -d -m 0755 "${service_dir}/dependencies.d"
printf 'longrun\n' >"${service_dir}/type"
touch "${service_dir}/dependencies.d/base"
if [ -d /etc/s6-overlay/s6-rc.d/ansible-setup ]; then
    touch "${service_dir}/dependencies.d/ansible-setup"
fi
printf -v quoted_user '%q' "${service_user}"
printf -v quoted_home '%q' "${service_home}"
cat >"${service_dir}/run" <<EOF
#!/command/with-contenv bash
exec s6-setuidgid ${quoted_user} env HOME=${quoted_home} USER=${quoted_user} /usr/local/bin/openobserve-service
EOF
chmod 0755 "${service_dir}/run"
touch /etc/s6-overlay/user-bundles.d/user/contents.d/openobserve

if [ -n "${DNSNAME}" ]; then
    cat >/etc/caddy/conf.d/openobserve.caddy <<EOF
${DNSNAME} {
    reverse_proxy 127.0.0.1:${PORT}
}
EOF
    chmod 0644 /etc/caddy/conf.d/openobserve.caddy
    printf '%s\n' "${DNSNAME}" >/etc/caddy/required-hosts.d/openobserve.host
    chmod 0644 /etc/caddy/required-hosts.d/openobserve.host
    log "Configured https://${DNSNAME} to proxy to OpenObserve on 127.0.0.1:${PORT}."
fi

/usr/local/bin/openobserve --version >/dev/null
rm -rf /var/lib/apt/lists/*
log "Installed OpenObserve ${normalized_version} as an s6 service running as ${service_user}."
