#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    echo "[caddy-header-auth] $*"
}

err() {
    echo "[caddy-header-auth] ERROR: $*" >&2
    exit 1
}

pick_service_user() {
    local requested="${1:-automatic}"
    local candidate

    if [ -n "${requested}" ] && [ "${requested}" != automatic ] && [ "${requested}" != auto ]; then
        id -u "${requested}" >/dev/null 2>&1 || err "Requested serviceUser '${requested}' does not exist."
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

pick_socket_group() {
    local requested="${1:-automatic}"
    local service_user="$2"

    if [ -n "${requested}" ] && [ "${requested}" != automatic ] && [ "${requested}" != auto ]; then
        getent group "${requested}" >/dev/null 2>&1 || err "Requested socketGroup '${requested}' does not exist."
        echo "${requested}"
        return
    fi

    if getent group caddy >/dev/null 2>&1; then
        echo "caddy"
        return
    fi

    id -gn "${service_user}"
}

validate_abs_path() {
    local name="$1"
    local value="$2"

    [ -n "${value}" ] || err "${name} must not be empty."
    case "${value}" in
        /*) ;;
        *) err "${name} must be an absolute path: ${value}" ;;
    esac
    case "${value}" in
        *$'\n'*|*$'\r'*|*$'\t'*|*' '*|*'{'*|*'}'*|*"'"*|*'"'*|*';'*|*'$'*|*'`'*|*'\\'*)
            err "${name} contains unsupported characters: ${value}"
            ;;
    esac
    case "/${value}/" in
        */../*) err "${name} must not contain '..' path segments: ${value}" ;;
    esac
}

[ "$(id -u)" -eq 0 ] || err "This Feature must run as root."
[ -r /etc/os-release ] || err "Unable to detect Linux distribution."
# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-} ${ID_LIKE:-}" in
    *debian*|*ubuntu*) ;;
    *) err "This Feature currently supports Debian/Ubuntu-based images." ;;
esac

for required_path in /init /command/s6-rc /etc/s6-overlay/s6-rc.d /etc/s6-overlay/user-bundles.d/user/contents.d; do
    [ -e "${required_path}" ] || err "This Feature requires an s6-overlay 3 image with /init as PID 1."
done

case "$(uname -m)" in
    x86_64|amd64|arm64|aarch64) ;;
    *) err "Unsupported architecture: $(uname -m)." ;;
esac

service_user="$(pick_service_user "${SERVICEUSER:-automatic}")"
socket_group="$(pick_socket_group "${SOCKETGROUP:-automatic}" "${service_user}")"
socket_path="${SOCKETPATH:-/run/caddy-header-auth/auth.sock}"
config_dir="${CONFIGDIR:-/etc/caddy-header-auth/conf.d}"
timeout_seconds="${TIMEOUTSECONDS:-10}"

validate_abs_path socketPath "${socket_path}"
validate_abs_path configDir "${config_dir}"
case "${socket_path}" in
    */) err "socketPath must name a socket file, not a directory: ${socket_path}" ;;
esac
socket_dir="$(dirname "${socket_path}")"
[ "${socket_dir}" != "/" ] || err "socketPath must live inside a dedicated directory, not /."

[[ "${timeout_seconds}" =~ ^[1-9][0-9]*$ ]] && [ "${timeout_seconds}" -le 300 ] \
    || err "timeoutSeconds must be an integer between 1 and 300."

service_home="$(getent passwd "${service_user}" | cut -d: -f6)"
[ -n "${service_home}" ] || err "Unable to resolve home directory for '${service_user}'."

if ! command -v python3 >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends python3
    rm -rf /var/lib/apt/lists/*
fi
python3 --version >/dev/null 2>&1 || err "python3 installation failed."

install -d -m 0755 -o root -g root /usr/local/lib/caddy-header-auth
install -m 0755 -o root -g root "${script_dir}/server.py" /usr/local/lib/caddy-header-auth/server.py
install -d -m 0755 -o root -g root "${config_dir}"

printf -v quoted_socket_path '%q' "${socket_path}"
printf -v quoted_socket_dir '%q' "${socket_dir}"
printf -v quoted_config_dir '%q' "${config_dir}"
printf -v quoted_timeout '%q' "${timeout_seconds}"
printf -v quoted_service_user '%q' "${service_user}"
printf -v quoted_socket_group '%q' "${socket_group}"
printf -v quoted_service_home '%q' "${service_home}"

cat >/usr/local/bin/caddy-header-auth-service <<EOF
#!/usr/bin/env bash
set -euo pipefail

exec python3 /usr/local/lib/caddy-header-auth/server.py \\
    --socket ${quoted_socket_path} \\
    --config-dir ${quoted_config_dir} \\
    --timeout ${quoted_timeout}
EOF
chmod 0755 /usr/local/bin/caddy-header-auth-service

service_dir=/etc/s6-overlay/s6-rc.d/caddy-header-auth
install -d -m 0755 "${service_dir}/dependencies.d"
printf 'longrun\n' >"${service_dir}/type"
touch "${service_dir}/dependencies.d/base"
if [ -d /etc/s6-overlay/s6-rc.d/ansible-setup ]; then
    touch "${service_dir}/dependencies.d/ansible-setup"
fi
cat >"${service_dir}/run" <<EOF
#!/command/with-contenv bash
set -euo pipefail
install -d -m 2750 -o ${quoted_service_user} -g ${quoted_socket_group} ${quoted_socket_dir}
exec s6-setuidgid ${quoted_service_user} env HOME=${quoted_service_home} USER=${quoted_service_user} /usr/local/bin/caddy-header-auth-service
EOF
chmod 0755 "${service_dir}/run"

touch /etc/s6-overlay/user-bundles.d/user/contents.d/caddy-header-auth

log "Installed caddy-header-auth for ${service_user} (socket group ${socket_group}, socket ${socket_path})."
