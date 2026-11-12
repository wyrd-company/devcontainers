#!/usr/bin/env bash

set -euo pipefail

log() {
    echo "[vector] $*"
}

err() {
    echo "[vector] ERROR: $*" >&2
    exit 1
}

pick_service_user() {
    local requested="${1:-automatic}"
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

# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

[ "$(id -u)" -eq 0 ] || err "This Feature must run as root."
[ -r /etc/os-release ] || err "Unable to detect Linux distribution."

requested_version="${VERSION:-latest}"
service_user_request="${SERVICEUSER:-automatic}"
api_address="$(normalize_api_address "${APIADDRESS-127.0.0.1:8686}")"
watch_method="${WATCHCONFIGMETHOD:-recommended}"
poll_interval="${WATCHCONFIGPOLLINTERVALSECONDS:-30}"

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

case "${watch_method}" in
    recommended|poll) ;;
    *) err "watchConfigMethod must be 'recommended' or 'poll'." ;;
esac
[[ "${poll_interval}" =~ ^[1-9][0-9]{0,4}$ ]] \
    || err "watchConfigPollIntervalSeconds must be a whole number of seconds from 1 to 99999."

case "$(uname -m)" in
    x86_64|amd64) target=x86_64-unknown-linux-gnu ;;
    arm64|aarch64) target=aarch64-unknown-linux-gnu ;;
    *) err "Unsupported architecture: $(uname -m)." ;;
esac

if [ "${requested_version}" != latest ]; then
    [[ "${requested_version}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] \
        || err "version must be 'latest' or a semantic version such as '0.61.0'."
fi

service_user="$(pick_service_user "${service_user_request}")"
service_group="$(id -gn "${service_user}")"
service_home="$(getent passwd "${service_user}" | cut -d: -f6)"
[ -n "${service_home}" ] || err "Unable to resolve the home directory for ${service_user}."

# Rendered secret files from the OpenBao Agent Feature are group-readable.
if [ "${service_user}" != root ] && getent group openbao-secrets >/dev/null 2>&1; then
    usermod -aG openbao-secrets "${service_user}"
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends ca-certificates curl jq

download_dir="$(mktemp -d)"
trap 'rm -rf "${download_dir}"' EXIT

if [ "${requested_version}" = latest ]; then
    log "Resolving the latest stable Vector release..."
    normalized_version="$(resolve_latest_version)"
else
    normalized_version="${requested_version#v}"
fi

archive_name="vector-${normalized_version}-${target}.tar.gz"
checksums_name="vector-${normalized_version}-SHA256SUMS"
release_url="https://github.com/vectordotdev/vector/releases/download/v${normalized_version}"
archive="${download_dir}/${archive_name}"
checksums_file="${download_dir}/${checksums_name}"

log "Downloading Vector ${normalized_version} for ${target}."
curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
    --output "${checksums_file}" "${release_url}/${checksums_name}"
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
binary="${extract_dir}/vector-${target}/bin/vector"
[ -x "${binary}" ] || err "The release archive did not contain bin/vector."
install -m 0755 "${binary}" /usr/local/bin/vector

case "$(/usr/local/bin/vector --version)" in
    "vector ${normalized_version} "*) ;;
    *) err "Installed Vector reports '$(/usr/local/bin/vector --version)', expected ${normalized_version}." ;;
esac

config_file=/etc/vector/vector.yaml
config_dir=/etc/vector/conf.d
data_dir=/var/lib/vector

install -d -m 0755 -o root -g root /etc/vector
# Pipelines can run commands through the exec source, so only the service user
# (and root) may write them.
install -d -m 0755 -o "${service_user}" -g "${service_group}" "${config_dir}"
install -d -m 0750 -o "${service_user}" -g "${service_group}" "${data_dir}"

{
    echo '# Managed by the Vector devcontainer Feature. Add pipelines to /etc/vector/conf.d.'
    printf 'data_dir: %s\n' "${data_dir}"
    echo 'api:'
    if [ -n "${api_address}" ]; then
        echo '  enabled: true'
        printf '  address: "%s"\n' "${api_address}"
    else
        echo '  enabled: false'
    fi
    # Vector resolves secret placeholders even inside comments, so none is written here.
    echo '# The environment backend reads variables of the service environment.'
    echo 'secret:'
    echo '  environment:'
    echo '    type: exec'
    echo '    command:'
    echo '      - /usr/local/bin/vector-secret-environment'
} >"${config_file}"
chmod 0644 "${config_file}"

# Vector refuses to validate a configuration without components, so a stub
# pipeline lets Vector itself check the generated file, including apiAddress.
check_dir="${download_dir}/check.d"
install -d -m 0755 "${check_dir}"
cat >"${check_dir}/stub.yaml" <<'EOF'
sources:
  feature_check_source:
    type: demo_logs
    format: json
sinks:
  feature_check_sink:
    type: blackhole
    inputs: [feature_check_source]
EOF
check_output="$(/usr/local/bin/vector validate --no-environment \
    --config-dir "${check_dir}" "${config_file}" 2>&1)" \
    || err "Vector rejected the generated configuration; check apiAddress. ${check_output}"

cat >/usr/local/bin/vector-secret-environment <<'EOF'
#!/usr/bin/env bash
# Vector exec secret backend: answers SECRET[environment.NAME] from the
# environment of the Vector process, which includes the OpenBao secret file.
set -euo pipefail

exec jq --compact-output '
    (.secrets // [])
    | map({
        key: .,
        value: (
            if test("^[A-Za-z_][A-Za-z0-9_]*$") and ($ENV[.] != null)
            then {value: $ENV[.], error: null}
            else {value: null, error: "environment variable is not set"}
            end
        )
    })
    | from_entries
'
EOF
chmod 0755 /usr/local/bin/vector-secret-environment

printf -v quoted_config_file '%q' "${config_file}"
printf -v quoted_config_dir '%q' "${config_dir}"
printf -v quoted_watch_method '%q' "${watch_method}"
printf -v quoted_poll_interval '%q' "${poll_interval}"
# The launcher runs with the user's environment, so its own variables carry a
# reserved prefix and are never exported. Secret file values reach Vector only
# through `env`, so a key can share a name with any launcher variable.
cat >/usr/local/bin/vector-service <<EOF
#!/usr/bin/env bash
set -euo pipefail

__vector_service_config_file=${quoted_config_file}
__vector_service_config_dir=${quoted_config_dir}
__vector_service_watch_method=${quoted_watch_method}
__vector_service_poll_interval=${quoted_poll_interval}
EOF
cat >>/usr/local/bin/vector-service <<'EOF'

# Names exported by the container, captured before the launcher assigns anything
# that could shadow them.
declare -A __vector_service_incoming=()
while IFS= read -r __vector_service_name; do
    __vector_service_incoming["${__vector_service_name}"]=1
done < <(compgen -e)

# The Feature manages these settings. Some would add configuration beside the
# managed files, and Vector parses all of them even for subcommands.
__vector_service_managed=(
    VECTOR_CONFIG VECTOR_CONFIG_DIR VECTOR_CONFIG_TOML VECTOR_CONFIG_JSON VECTOR_CONFIG_YAML
    VECTOR_WATCH_CONFIG VECTOR_WATCH_CONFIG_METHOD VECTOR_WATCH_CONFIG_POLL_INTERVAL_SECONDS
    VECTOR_ALLOW_EMPTY_CONFIG
)

__vector_service_mode=run
if [ "${1:-}" = validate ]; then
    __vector_service_mode=validate
    shift
fi

__vector_service_secret_file=/run/openbao/secrets/vector.env
__vector_service_secrets=()
if [ "${__vector_service_mode}" = run ] && [ -x /usr/local/bin/openbao-wait-for-secrets ]; then
    /usr/local/bin/openbao-wait-for-secrets vector
fi
if [ -e "${__vector_service_secret_file}" ] && [ ! -r "${__vector_service_secret_file}" ]; then
    echo "[vector] ERROR: ${__vector_service_secret_file} exists but is not readable by $(id -un)." >&2
    exit 1
fi
if [ -r "${__vector_service_secret_file}" ]; then
    # Values are literal text, not shell. The container environment takes precedence.
    while IFS= read -r __vector_service_line || [ -n "${__vector_service_line}" ]; do
        __vector_service_line="${__vector_service_line#"${__vector_service_line%%[![:space:]]*}"}"
        case "${__vector_service_line}" in
            ''|'#'*) continue ;;
        esac
        __vector_service_name="${__vector_service_line%%=*}"
        if [ "${__vector_service_name}" = "${__vector_service_line}" ] \
            || ! [[ "${__vector_service_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            echo "[vector] ERROR: ${__vector_service_secret_file} contains a line that is not NAME=value." >&2
            exit 1
        fi
        for __vector_service_setting in "${__vector_service_managed[@]}"; do
            if [ "${__vector_service_name}" = "${__vector_service_setting}" ]; then
                echo "[vector] ERROR: ${__vector_service_secret_file} sets ${__vector_service_name}, which the Feature manages." >&2
                exit 1
            fi
        done
        if [ -z "${__vector_service_incoming["${__vector_service_name}"]+x}" ]; then
            __vector_service_secrets+=("${__vector_service_line}")
        fi
    done <"${__vector_service_secret_file}"
fi

unset "${__vector_service_managed[@]}"

if [ "${__vector_service_mode}" = validate ]; then
    exec env -- "${__vector_service_secrets[@]}" /usr/local/bin/vector validate \
        --no-environment --resolve-secrets \
        --config-dir "${__vector_service_config_dir}" "$@" "${__vector_service_config_file}"
fi

exec env -- "${__vector_service_secrets[@]}" /usr/local/bin/vector \
    --config "${__vector_service_config_file}" \
    --config-dir "${__vector_service_config_dir}" \
    --watch-config \
    --watch-config-method "${__vector_service_watch_method}" \
    --watch-config-poll-interval-seconds "${__vector_service_poll_interval}" \
    --allow-empty-config \
    "$@"
EOF
chmod 0755 /usr/local/bin/vector-service

service_dir=/etc/s6-overlay/s6-rc.d/vector
install -d -m 0755 "${service_dir}/dependencies.d"
printf 'longrun\n' >"${service_dir}/type"
touch "${service_dir}/dependencies.d/base"
if [ -d /etc/s6-overlay/s6-rc.d/ansible-setup ]; then
    touch "${service_dir}/dependencies.d/ansible-setup"
fi
if [ -d /etc/s6-overlay/s6-rc.d/openbao-secrets ]; then
    touch "${service_dir}/dependencies.d/openbao-secrets"
fi
printf -v quoted_user '%q' "${service_user}"
printf -v quoted_home '%q' "${service_home}"
cat >"${service_dir}/run" <<EOF
#!/command/with-contenv bash
exec s6-setuidgid ${quoted_user} env HOME=${quoted_home} USER=${quoted_user} /usr/local/bin/vector-service
EOF
chmod 0755 "${service_dir}/run"
touch /etc/s6-overlay/user-bundles.d/user/contents.d/vector

rm -rf /var/lib/apt/lists/*
log "Installed Vector ${normalized_version} as an s6 service running as ${service_user}; add pipelines to ${config_dir}."
