#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

require_root

[ -r /etc/os-release ] || err "Unable to detect Linux distribution."
# shellcheck disable=SC1091
distribution_family="$(source /etc/os-release; printf '%s %s' "${ID:-}" "${ID_LIKE:-}")"
case "${distribution_family}" in
    *debian*|*ubuntu*) ;;
    *) err "This Feature currently supports Debian/Ubuntu-based images." ;;
esac
case "$(uname -m)" in
    x86_64|amd64|aarch64|arm64) ;;
    *) err "Unsupported architecture: $(uname -m)." ;;
esac

start_app_server="${STARTAPPSERVER:-true}"
remote_control="${REMOTECONTROL:-false}"
case "${start_app_server}" in true|false) ;; *) err "startAppServer must be true or false." ;; esac
case "${remote_control}" in true|false) ;; *) err "remoteControl must be true or false." ;; esac
if [ "${remote_control}" = true ] && [ "${start_app_server}" != true ]; then
    err "remoteControl requires startAppServer."
fi
if [ "${start_app_server}" = true ]; then
    for required_path in /init /command/s6-rc /etc/s6-overlay/s6-rc.d /etc/s6-overlay/user-bundles.d/user/contents.d; do
        [ -e "${required_path}" ] || err "This Feature requires an s6-overlay 3 image, or startAppServer=false."
    done
fi

devcontainer_user="$(pick_devcontainer_user "${SERVICEUSER:-automatic}")"
user_home="$(user_home_dir "${devcontainer_user}")"
[ -n "${user_home}" ] || err "Unable to resolve the home directory for ${devcontainer_user}."

install -d -m 0755 -o "${devcontainer_user}" -g "$(id -gn "${devcontainer_user}")" "${user_home}/.local"

package_spec="@openai/codex@${VERSION}"
log "Installing ${package_spec} for ${devcontainer_user}"
run_as_user "${devcontainer_user}" env \
    HOME="${user_home}" \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    npm install --global --prefix "${user_home}/.local" "${package_spec}"

codex_binary="${user_home}/.local/bin/codex"
[ -x "${codex_binary}" ] || err "Codex CLI was not installed at ${codex_binary}."
ln -sf "${codex_binary}" /usr/local/bin/codex

log "Installed Codex CLI $(run_as_user "${devcontainer_user}" env HOME="${user_home}" "${codex_binary}" --version)"

if [ "${start_app_server}" = true ]; then
    printf -v quoted_user '%q' "${devcontainer_user}"
    printf -v quoted_home '%q' "${user_home}"
    printf -v quoted_binary '%q' "${codex_binary}"
    remote_control_flag=
    remote_control_disabled=1
    if [ "${remote_control}" = true ]; then
        remote_control_flag=--remote-control
        remote_control_disabled=0
    fi
    cat >/usr/local/bin/codex-cli-service <<EOF
#!/usr/bin/env bash
set -euo pipefail
# Use Codex's own daemon marker so that false does not restore saved preferences.
exec env CODEX_INTERNAL_APP_SERVER_REMOTE_CONTROL_DISABLED=${remote_control_disabled} ${quoted_binary} app-server --listen unix:// ${remote_control_flag}
EOF
    chmod 0755 /usr/local/bin/codex-cli-service

    service_dir=/etc/s6-overlay/s6-rc.d/codex-cli
    install -d -m 0755 "${service_dir}/dependencies.d"
    printf 'longrun\n' >"${service_dir}/type"
    touch "${service_dir}/dependencies.d/base"
    cat >"${service_dir}/run" <<EOF
#!/command/with-contenv bash
exec s6-setuidgid ${quoted_user} env HOME=${quoted_home} USER=${quoted_user} /usr/local/bin/codex-cli-service
EOF
    chmod 0755 "${service_dir}/run"
    touch /etc/s6-overlay/user-bundles.d/user/contents.d/codex-cli
    log "Configured shared Codex app-server as ${devcontainer_user} (remote control: ${remote_control})."
fi
