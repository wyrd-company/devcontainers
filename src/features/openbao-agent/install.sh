#!/usr/bin/env bash

set -euo pipefail

log() {
    echo "[openbao-agent] $*"
}

err() {
    echo "[openbao-agent] ERROR: $*" >&2
    exit 1
}

pick_service_user() {
    local requested="${1:-root}"
    local candidate

    if [ -n "${requested}" ] && [ "${requested}" != automatic ] && [ "${requested}" != auto ]; then
        id -u "${requested}" >/dev/null 2>&1 \
            || err "Requested service user '${requested}' does not exist."
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
    local releases_json version page=1
    local -a curl_args=(
        --fail
        --location
        --silent
        --show-error
        --retry 3
        -H "Accept: application/vnd.github+json"
    )

    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi

    while :; do
        releases_json="$(curl "${curl_args[@]}" \
            "https://api.github.com/repos/openbao/openbao/releases?per_page=20&page=${page}")" \
            || err "Unable to query OpenBao releases. Set 'version' to a published version and retry."

        version="$(printf '%s\n' "${releases_json}" | jq -r \
            --arg architecture "${architecture}" '
                [
                    .[]
                    | select(.draft == false and .prerelease == false)
                    | (.tag_name | ltrimstr("v")) as $version
                    | select(any(
                        .assets[]?;
                        .name == ("openbao_" + $version + "_linux_" + $architecture + ".tar.gz")
                      ))
                    | $version
                ]
                | first // empty
            ')"

        if [ -n "${version}" ]; then
            echo "${version}"
            return
        fi
        [ "$(printf '%s\n' "${releases_json}" | jq 'length')" -gt 0 ] || break
        page=$((page + 1))
    done

    err "No stable OpenBao release contains a Linux ${architecture} archive."
}

[ "$(id -u)" -eq 0 ] || err "This Feature must run as root."
[ -r /etc/os-release ] || err "Unable to detect Linux distribution."

requested_version="${VERSION:-latest}"
service_user_request="${SERVICEUSER:-root}"
config_path="${CONFIGPATH:-/etc/openbao/agent.hcl}"

# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-} ${ID_LIKE:-}" in
    *debian*|*ubuntu*) ;;
    *) err "This Feature currently supports Debian/Ubuntu-based images." ;;
esac

for required_path in /init /command/s6-rc /etc/s6-overlay/s6-rc.d /etc/s6-overlay/user-bundles.d/user/contents.d; do
    [ -e "${required_path}" ] \
        || err "This Feature requires an s6-overlay 3 image with /init as PID 1."
done

case "${config_path}" in
    /*) ;;
    *) err "configPath must be an absolute path." ;;
esac
[ "${config_path}" != / ] || err "configPath must identify a file, not '/'."
case "${config_path}" in
    *$'\n'*|*$'\r'*) err "configPath contains unsupported characters." ;;
esac

case "$(uname -m)" in
    x86_64|amd64) architecture=amd64 ;;
    arm64|aarch64) architecture=arm64 ;;
    *) err "Unsupported architecture: $(uname -m)." ;;
esac

service_user="$(pick_service_user "${service_user_request}")"
service_home="$(getent passwd "${service_user}" | cut -d: -f6)"
[ -n "${service_home}" ] || err "Unable to resolve the home directory for ${service_user}."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends ca-certificates curl jq

download_dir="$(mktemp -d)"
trap 'rm -rf "${download_dir}"' EXIT

if [ "${requested_version}" = latest ]; then
    log "Resolving the latest stable OpenBao release for Linux ${architecture}..."
    normalized_version="$(resolve_latest_version)"
else
    [[ "${requested_version}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]] \
        || err "version must be 'latest' or a semantic version such as '2.6.2'."
    normalized_version="${requested_version#v}"
fi

archive_name="openbao_${normalized_version}_linux_${architecture}.tar.gz"
release_url="https://github.com/openbao/openbao/releases/download/v${normalized_version}"
archive="${download_dir}/${archive_name}"
checksums_file="${download_dir}/checksums.txt"

log "Downloading OpenBao ${normalized_version} for Linux ${architecture}."
curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
    --output "${checksums_file}" "${release_url}/checksums.txt"
curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
    --output "${archive}" "${release_url}/${archive_name}"

expected_checksum="$(awk -v archive="${archive_name}" '$2 == archive { print $1 }' "${checksums_file}")"
[[ "${expected_checksum}" =~ ^[0-9a-fA-F]{64}$ ]] \
    || err "No valid checksum was published for ${archive_name}."
printf '%s  %s\n' "${expected_checksum}" "${archive}" | sha256sum --check --status \
    || err "Checksum verification failed for ${archive_name}."

extract_dir="${download_dir}/extract"
install -d -m 0755 "${extract_dir}"
tar -xzf "${archive}" -C "${extract_dir}"
[ -x "${extract_dir}/bao" ] || err "The OpenBao release did not contain an executable named bao."
install -m 0755 "${extract_dir}/bao" /usr/local/bin/bao

config_dir="$(dirname "${config_path}")"
install -d -m 0755 "${config_dir}"

getent group openbao-secrets >/dev/null 2>&1 || groupadd --system openbao-secrets

printf -v quoted_bao '%q' /usr/local/bin/bao
printf -v quoted_config '%q' "${config_path}"
printf -v quoted_user '%q' "${service_user}"
printf -v quoted_home '%q' "${service_home}"

cat >/usr/local/bin/openbao-prepare-secrets <<EOF
#!/usr/bin/env bash
set -euo pipefail

parent_dir=/run/openbao
secrets_dir="\${parent_dir}/secrets"

# The Feature owns the render directory. It never removes through a symlinked
# component or through a mount at or below the parent.
for path in "\${parent_dir}" "\${secrets_dir}"; do
    if [ -L "\${path}" ]; then
        echo "[openbao-secrets] ERROR: \${path} is a symbolic link; the Feature owns \${secrets_dir} and does not clear linked paths." >&2
        exit 1
    fi
done
mounted="\$(findmnt --raw --noheadings --output TARGET | grep -E "^\${parent_dir}(/|\$)" || true)"
if [ -n "\${mounted}" ]; then
    echo "[openbao-secrets] ERROR: \${mounted//\$'\\n'/, } is a mount point; the Feature owns \${secrets_dir} and does not clear mounted paths." >&2
    exit 1
fi

# Files from a previous container start must not satisfy openbao-wait-for-secrets.
rm -rf "\${secrets_dir}"
install -d -m 0755 -o root -g root /run/openbao
install -d -m 2750 -o ${quoted_user} -g openbao-secrets "\${secrets_dir}"
EOF
chmod 0755 /usr/local/bin/openbao-prepare-secrets

cat >/usr/local/bin/openbao-wait-for-secrets <<EOF
#!/usr/bin/env bash
set -euo pipefail

config_path=${quoted_config}

if [ "\$#" -ne 1 ] || ! [[ "\$1" =~ ^[a-z0-9][a-z0-9-]*\$ ]]; then
    echo "usage: openbao-wait-for-secrets <feature-id>" >&2
    exit 2
fi
secret_file="/run/openbao/secrets/\$1.env"

configuration_files=()
if [ -d "\${config_path}" ]; then
    while IFS= read -r -d '' file; do
        configuration_files+=("\${file}")
    done < <(find "\${config_path}" -type f \\( -name '*.hcl' -o -name '*.json' \\) -print0 2>/dev/null)
else
    configuration_files=("\${config_path}")
fi
for file in "\${config_path}" "\${configuration_files[@]}"; do
    if [ ! -r "\${file}" ]; then
        echo "[openbao-wait-for-secrets] Configuration is not readable at \${file}; not waiting for \${secret_file}." >&2
        exit 0
    fi
done

# The Agent configuration declares which files are expected: a template whose
# destination is the conventional path, in HCL or JSON form. Comments, other
# assignments, and longer paths that contain this one do not count.
configuration_text() {
    cat "\${configuration_files[@]}"
}
strip_block_comments() {
    sed --null-data --regexp-extended 's#/\\*([^*]|\\*+[^*/])*\\*+/##g'
}
escaped_file="\${secret_file//./\\\\.}"
pattern='^[[:space:]]*"?destination"?[[:space:]]*[=:][[:space:]]*"'"\${escaped_file}"'"[[:space:]]*,?[[:space:]]*(#.*|//.*)?$'
if ! configuration_text | strip_block_comments | tr -d '\\0' | grep --extended-regexp --quiet -- "\${pattern}"; then
    exit 0
fi

while [ ! -e "\${secret_file}" ]; do
    echo "[openbao-wait-for-secrets] Waiting for \${secret_file}" >&2
    sleep 1
done
EOF
chmod 0755 /usr/local/bin/openbao-wait-for-secrets

cat >/usr/local/bin/openbao-agent-service <<EOF
#!/usr/bin/env bash
set -euo pipefail

config_path=${quoted_config}
if [ ! -r "\${config_path}" ]; then
    echo "[openbao-agent] ERROR: Configuration is not readable at \${config_path}." >&2
    exit 1
fi

exec ${quoted_bao} agent -config="\${config_path}" "\$@"
EOF
chmod 0755 /usr/local/bin/openbao-agent-service

secrets_dir=/etc/s6-overlay/s6-rc.d/openbao-secrets
install -d -m 0755 "${secrets_dir}/dependencies.d"
printf 'oneshot\n' >"${secrets_dir}/type"
touch "${secrets_dir}/dependencies.d/base"
printf '/usr/local/bin/openbao-prepare-secrets\n' >"${secrets_dir}/up"
touch /etc/s6-overlay/user-bundles.d/user/contents.d/openbao-secrets

service_dir=/etc/s6-overlay/s6-rc.d/openbao-agent
install -d -m 0755 "${service_dir}/dependencies.d"
printf 'longrun\n' >"${service_dir}/type"
touch "${service_dir}/dependencies.d/base"
touch "${service_dir}/dependencies.d/openbao-secrets"
cat >"${service_dir}/run" <<EOF
#!/command/with-contenv bash
exec s6-setuidgid ${quoted_user} env HOME=${quoted_home} USER=${quoted_user} /usr/local/bin/openbao-agent-service
EOF
chmod 0755 "${service_dir}/run"
touch /etc/s6-overlay/user-bundles.d/user/contents.d/openbao-agent

# A service Feature installed before this one could not see the group or the
# oneshot. Its launcher names the wait helper, so reconcile it here.
for run_file in /etc/s6-overlay/s6-rc.d/*/run; do
    [ -f "${run_file}" ] || continue
    consumer_dir="$(dirname "${run_file}")"
    [ "${consumer_dir}" != "${service_dir}" ] || continue
    launcher="$(grep -oE '/usr/local/bin/[A-Za-z0-9._-]+' "${run_file}" | tail -n 1 || true)"
    [ -n "${launcher}" ] && [ -f "${launcher}" ] || continue
    grep -Fq openbao-wait-for-secrets "${launcher}" || continue
    install -d -m 0755 "${consumer_dir}/dependencies.d"
    touch "${consumer_dir}/dependencies.d/openbao-secrets"
    consumer_user="$(sed -nE 's/^exec s6-setuidgid ([^ ]+) .*/\1/p' "${run_file}" | head -n 1)"
    if [ -n "${consumer_user}" ] && [ "${consumer_user}" != root ] && id -u "${consumer_user}" >/dev/null 2>&1; then
        usermod -aG openbao-secrets "${consumer_user}"
    fi
    log "Reconciled $(basename "${consumer_dir}") to start after the secret file directory exists."
done

/usr/local/bin/bao version >/dev/null
rm -rf /var/lib/apt/lists/*
log "Installed OpenBao ${normalized_version}; OpenBao Agent will run as ${service_user} using ${config_path}."
