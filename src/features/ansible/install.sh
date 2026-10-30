#!/usr/bin/env bash

set -euo pipefail

log() {
    echo "[ansible] $*"
}

err() {
    echo "[ansible] ERROR: $*" >&2
    exit 1
}

pick_service_user() {
    local requested="${1:-root}"
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

# A relative path inside the playbook source: no leading slash, dash or dot-dot component.
validate_relative_path() {
    local option="$1"
    local value="$2"

    [[ "${value}" =~ ^[A-Za-z0-9_][A-Za-z0-9_./-]*$ ]] \
        || err "${option} must be a relative path of letters, digits, '_', '.', '/' and '-'."
    case "/${value}/" in
        */../*|*//*) err "${option} must not contain '..' or empty path components." ;;
    esac
}

validate_absolute_path() {
    local option="$1"
    local value="$2"

    [[ "${value}" =~ ^/[A-Za-z0-9_./-]+$ ]] \
        || err "${option} must be an absolute path of letters, digits, '_', '.', '/' and '-'."
    case "${value}/" in
        */../*|*//*|*/./*) err "${option} must not contain '.', '..' or empty path components." ;;
    esac
}

validate_source() {
    local value="$1"
    local authority

    case "${value}" in
        /*)
            validate_absolute_path source "${value}"
            ;;
        https://*|ssh://*|file://*)
            [[ "${value}" =~ ^[A-Za-z0-9._~:/@%+,=-]+$ ]] \
                || err "source contains unsupported characters."
            authority="${value#*://}"
            authority="${authority%%/*}"
            case "${value}" in
                ssh://*) [[ "${authority%@*}" != *:* ]] || err "source must not embed a password." ;;
                *) [[ "${authority}" != *@* ]] || err "source must not embed credentials." ;;
            esac
            ;;
        *)
            [[ "${value}" =~ ^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:[A-Za-z0-9_./+%-]+$ ]] \
                || err "source must be an absolute path, an https://, ssh:// or file:// URL, or user@host:path."
            ;;
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

feature_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source_value="${SOURCE:-}"
playbook="${PLAYBOOK:-site.yml}"
ref="${REF:-}"
inventory="${INVENTORY:-}"
requirements="${REQUIREMENTS:-}"
extra_args="${ARGS:-}"
checkout_dir="${CHECKOUTDIR:-/var/lib/ansible-setup/checkout}"

if [ -n "${source_value}" ]; then
    validate_source "${source_value}"
fi
validate_relative_path playbook "${playbook}"
if [ -n "${ref}" ]; then
    [[ "${ref}" =~ ^[A-Za-z0-9][A-Za-z0-9_./-]*$ ]] \
        || err "ref must be a branch, tag or commit of letters, digits, '_', '.', '/' and '-'."
    case "/${ref}/" in
        */../*|*//*|*.lock/*) err "ref is not a valid Git reference." ;;
    esac
    case "${source_value}" in
        /*) err "ref is not valid with a local directory source; the directory is used as it is." ;;
    esac
fi
if [ -n "${inventory}" ]; then
    validate_relative_path inventory "${inventory}"
fi
if [ -n "${requirements}" ]; then
    validate_relative_path requirements "${requirements}"
fi
[[ "${extra_args}" =~ ^[A-Za-z0-9_@%+=:,./\ -]*$ ]] \
    || err "args contains characters that are not allowed: quotes, braces and other shell characters."
validate_absolute_path checkoutDir "${checkout_dir}"
state_dir=/var/lib/ansible-setup
case "${state_dir}/lock/" in
    "${checkout_dir}/"*) err "checkoutDir must not contain ${state_dir}/lock; choose a directory outside ${state_dir}." ;;
esac
case "${checkout_dir}/" in
    "${state_dir}/lock/"*) err "checkoutDir must not be ${state_dir}/lock or inside it." ;;
esac

service_user="$(pick_service_user "${SERVICEUSER:-root}")"
service_group="$(id -gn "${service_user}")"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends ansible-core ca-certificates git openssh-client util-linux

install -d -m 0755 -o "${service_user}" -g "${service_group}" "${state_dir}"
if [ -n "${source_value}" ]; then
    case "${source_value}" in
        /*) ;;
        *) install -d -m 0755 -o "${service_user}" -g "${service_group}" "${checkout_dir}" ;;
    esac
fi

printf -v q_source '%q' "${source_value}"
printf -v q_playbook '%q' "${playbook}"
printf -v q_ref '%q' "${ref}"
printf -v q_inventory '%q' "${inventory}"
printf -v q_requirements '%q' "${requirements}"
printf -v q_args '%q' "${extra_args}"
printf -v q_checkout '%q' "${checkout_dir}"
printf -v q_user '%q' "${service_user}"
printf -v q_state '%q' "${state_dir}"

# Non-secret settings. The command reads them; nothing here is a credential.
install -d -m 0755 /etc/ansible-setup
cat >/etc/ansible-setup/settings <<EOF
SETUP_SOURCE=${q_source}
SETUP_PLAYBOOK=${q_playbook}
SETUP_REF=${q_ref}
SETUP_INVENTORY=${q_inventory}
SETUP_REQUIREMENTS=${q_requirements}
SETUP_ARGS=${q_args}
SETUP_CHECKOUT=${q_checkout}
SETUP_USER=${q_user}
SETUP_STATE_DIR=${q_state}
EOF
chmod 0644 /etc/ansible-setup/settings

install -m 0755 "${feature_dir}/ansible-sync" /usr/local/bin/ansible-sync

# The s6 oneshot runs with the container environment, so the playbook sees the same
# variables as any process in the container.
cat >/usr/local/bin/ansible-setup <<'EOF'
#!/command/with-contenv bash
exec /usr/local/bin/ansible-sync --startup
EOF
chmod 0755 /usr/local/bin/ansible-setup

setup_dir=/etc/s6-overlay/s6-rc.d/ansible-setup
install -d -m 0755 "${setup_dir}/dependencies.d"
printf 'oneshot\n' >"${setup_dir}/type"
touch "${setup_dir}/dependencies.d/base"
printf '/usr/local/bin/ansible-setup\n' >"${setup_dir}/up"
touch /etc/s6-overlay/user-bundles.d/user/contents.d/ansible-setup

ansible-playbook --version >/dev/null
ansible-galaxy --version >/dev/null
rm -rf /var/lib/apt/lists/*
if [ -n "${source_value}" ]; then
    log "Installed Ansible; the ansible-setup oneshot applies ${playbook} from ${source_value} as ${service_user} at startup."
else
    log "Installed Ansible; no source is configured, so ansible-setup applies nothing."
fi
