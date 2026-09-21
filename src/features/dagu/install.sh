#!/usr/bin/env bash

set -euo pipefail

log() {
    echo "[dagu] $*"
}

err() {
    echo "[dagu] ERROR: $*" >&2
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

[ "$(id -u)" -eq 0 ] || err "This Feature must run as root."
[ -r /etc/os-release ] || err "Unable to detect Linux distribution."
requested_version="${VERSION}"
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

# Rendered secret files from the OpenBao Agent Feature are group-readable.
if [ "${service_user}" != root ] && getent group openbao-secrets >/dev/null 2>&1; then
    usermod -aG openbao-secrets "${service_user}"
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends ca-certificates curl

download_dir="$(mktemp -d)"
trap 'rm -rf "${download_dir}"' EXIT

if [ "${requested_version}" = latest ]; then
    release_path=latest/download
else
    [[ "${requested_version}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] \
        || err "version must be 'latest' or a semantic version such as '2.16.1'."
    normalized_version="${requested_version#v}"
    release_path="download/v${normalized_version}"
fi

release_url="https://github.com/dagu-org/dagu/releases/${release_path}"
checksums_file="${download_dir}/checksums.txt"
curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
    --output "${checksums_file}" "${release_url}/checksums.txt"

if [ "${requested_version}" = latest ]; then
    archive_name="$(awk -v suffix="_linux_${architecture}.tar.gz" '$2 ~ suffix "$" { print $2 }' "${checksums_file}")"
    [ -n "${archive_name}" ] || err "The latest release does not contain a Linux ${architecture} archive."
    [ "$(printf '%s\n' "${archive_name}" | wc -l)" -eq 1 ] \
        || err "The latest release contains multiple Linux ${architecture} archives."
    normalized_version="${archive_name#dagu_}"
    normalized_version="${normalized_version%_linux_"${architecture}".tar.gz}"
else
    archive_name="dagu_${normalized_version}_linux_${architecture}.tar.gz"
fi

expected_checksum="$(awk -v archive="${archive_name}" '$2 == archive { print $1 }' "${checksums_file}")"
[[ "${expected_checksum}" =~ ^[0-9a-f]{64}$ ]] \
    || err "No valid checksum was published for ${archive_name}."

archive="${download_dir}/${archive_name}"
log "Downloading Dagu ${normalized_version} for ${architecture}"
curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
    --output "${archive}" "${release_url}/${archive_name}"
printf '%s  %s\n' "${expected_checksum}" "${archive}" | sha256sum --check --status \
    || err "Checksum verification failed for ${archive_name}."

extract_dir="${download_dir}/extract"
install -d -m 0755 "${extract_dir}"
tar -xzf "${archive}" -C "${extract_dir}"
[ -x "${extract_dir}/dagu" ] || err "The Dagu release did not contain an executable named dagu."
install -m 0755 "${extract_dir}/dagu" /usr/local/bin/dagu

printf -v quoted_dagu '%q' /usr/local/bin/dagu
printf -v quoted_host '%q' "${normalized_host}"
printf -v quoted_port '%q' "${PORT}"
printf -v quoted_public_url '%q' "https://${DNSNAME}"

cat >/usr/local/bin/dagu-service <<EOF
#!/usr/bin/env bash
set -euo pipefail

EOF
if [ -n "${DNSNAME}" ]; then
    cat >>/usr/local/bin/dagu-service <<EOF
export DAGU_PUBLIC_URL=${quoted_public_url}
EOF
fi
cat >>/usr/local/bin/dagu-service <<EOF
secret_file=/run/openbao/secrets/dagu.env
if [ -x /usr/local/bin/openbao-wait-for-secrets ]; then
    /usr/local/bin/openbao-wait-for-secrets dagu
fi
if [ -r "\${secret_file}" ]; then
    # Values are literal text, not shell. The container environment takes precedence.
    while IFS= read -r line || [ -n "\${line}" ]; do
        line="\${line#"\${line%%[![:space:]]*}"}"
        case "\${line}" in
            ''|'#'*) continue ;;
        esac
        name="\${line%%=*}"
        if [ "\${name}" = "\${line}" ] || ! [[ "\${name}" =~ ^[A-Za-z_][A-Za-z0-9_]*\$ ]]; then
            echo "[dagu] ERROR: \${secret_file} contains a line that is not NAME=value." >&2
            exit 1
        fi
        if [ -z "\${!name+x}" ]; then
            export "\${name}=\${line#*=}"
        fi
    done <"\${secret_file}"
fi

exec ${quoted_dagu} start-all --host ${quoted_host} --port ${quoted_port} "\$@"
EOF
chmod 0755 /usr/local/bin/dagu-service

service_dir=/etc/s6-overlay/s6-rc.d/dagu
install -d -m 0755 "${service_dir}/dependencies.d"
printf 'longrun\n' >"${service_dir}/type"
touch "${service_dir}/dependencies.d/base"
if [ -d /etc/s6-overlay/s6-rc.d/openbao-secrets ]; then
    touch "${service_dir}/dependencies.d/openbao-secrets"
fi
printf -v quoted_user '%q' "${service_user}"
printf -v quoted_home '%q' "${service_home}"
cat >"${service_dir}/run" <<EOF
#!/command/with-contenv bash
exec s6-setuidgid ${quoted_user} env HOME=${quoted_home} USER=${quoted_user} /usr/local/bin/dagu-service
EOF
chmod 0755 "${service_dir}/run"
touch /etc/s6-overlay/user-bundles.d/user/contents.d/dagu

if [ -n "${DNSNAME}" ]; then
    cat >/etc/caddy/conf.d/dagu.caddy <<EOF
${DNSNAME} {
    reverse_proxy 127.0.0.1:${PORT}
}
EOF
    chmod 0644 /etc/caddy/conf.d/dagu.caddy
    printf '%s\n' "${DNSNAME}" >/etc/caddy/required-hosts.d/dagu.host
    chmod 0644 /etc/caddy/required-hosts.d/dagu.host
    log "Configured https://${DNSNAME} to proxy to Dagu on 127.0.0.1:${PORT}."
fi

/usr/local/bin/dagu version >/dev/null
rm -rf /var/lib/apt/lists/*
log "Installed Dagu ${normalized_version} as an s6 service running as ${service_user}."
