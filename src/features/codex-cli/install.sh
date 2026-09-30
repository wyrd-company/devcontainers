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
exec_server="${EXECSERVER-false}"
exec_port="${EXECSERVERPORT:-4501}"
app_port="${APPSERVERPORT:-4500}"
dns_name="${DNSNAME:-}"
if ! [[ "${exec_port}" =~ ^[0-9]{1,5}$ ]] || ! ((10#${exec_port} >= 1 && 10#${exec_port} <= 65535)); then
    err "execServerPort must be an integer from 1 to 65535."
fi
if ! [[ "${app_port}" =~ ^[0-9]{1,5}$ ]] || ! ((10#${app_port} >= 1 && 10#${app_port} <= 65535)); then
    err "appServerPort must be an integer from 1 to 65535."
fi
if [ -n "${dns_name}" ] && [ "${start_app_server}" = true ] && [ "${exec_server}" != false ] && ((10#${app_port} == 10#${exec_port})); then
    err "appServerPort and execServerPort must differ when both listeners are enabled."
fi
case "${start_app_server}" in true|false) ;; *) err "startAppServer must be true or false." ;; esac
case "${remote_control}" in true|false) ;; *) err "remoteControl must be true or false." ;; esac
if [ "${remote_control}" = true ] && [ "${start_app_server}" != true ]; then
    err "remoteControl requires startAppServer."
fi
if [ "${start_app_server}" = true ] || [ "${exec_server}" != false ]; then
    for required_path in /init /command/s6-rc /etc/s6-overlay/s6-rc.d /etc/s6-overlay/user-bundles.d/user/contents.d; do
        [ -e "${required_path}" ] || err "This Feature requires an s6-overlay 3 image, or both startAppServer=false and execServer=false."
    done
fi

if [ -n "${dns_name}" ]; then
    [ "${start_app_server}" = true ] || [ "${exec_server}" != false ] || err "dnsName requires an enabled app-server or exec-server."
    [[ "${dns_name}" =~ ^[A-Za-z0-9.-]+$ ]] || err "dnsName contains unsupported DNS characters."
    [ "${#dns_name}" -le 253 ] || err "dnsName exceeds the 253-character DNS limit."
    IFS=. read -r -a dns_labels <<<"${dns_name}"
    [ "${#dns_labels[@]}" -ge 2 ] || err "dnsName must be a fully qualified DNS name."
    for label in "${dns_labels[@]}"; do
        [[ "${label}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] || err "dnsName contains an invalid DNS label."
    done
    [ -d /etc/caddy/conf.d ] || err "dnsName requires the Caddy Feature and its /etc/caddy/conf.d directory."
    [ -d /etc/caddy/required-hosts.d ] || err "dnsName requires a Caddy Feature version with DNS readiness support."
fi

exec_args=()
if [ "${exec_server}" != false ] && [ "${exec_server}" != true ]; then
    arguments_dir=/usr/local/share/codex-cli-arguments
    install -d -m 0755 "${arguments_dir}"
    cp "$(dirname "$0")/arguments/"* "${arguments_dir}/"
    NPM_CONFIG_UPDATE_NOTIFIER=false npm install --prefix "${arguments_dir}" --omit=dev --ignore-scripts
    args_file="$(mktemp)"
    if ! node "${arguments_dir}/parse.cjs" "${exec_server}" >"${args_file}"; then
        rm -f "${args_file}"
        err "Unable to parse execServer arguments."
    fi
    mapfile -d '' -t exec_args <"${args_file}"
    rm -f "${args_file}"
fi

devcontainer_user="$(pick_devcontainer_user "${SERVICEUSER:-automatic}")"
user_home="$(user_home_dir "${devcontainer_user}")"
[ -n "${user_home}" ] || err "Unable to resolve the home directory for ${devcontainer_user}."

if [ -n "${dns_name}" ] && [ "${start_app_server}" = true ]; then
    apt-get update
    apt-get install -y --no-install-recommends socat
    rm -rf /var/lib/apt/lists/*
fi

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

if [ "${exec_server}" != false ]; then
    printf -v quoted_user '%q' "${devcontainer_user}"
    printf -v quoted_home '%q' "${user_home}"
    printf -v quoted_binary '%q' "${codex_binary}"
    exec_flags=
    if [ "${#exec_args[@]}" -gt 0 ]; then
        printf -v exec_flags ' %q' "${exec_args[@]}"
    fi
    cat >/usr/local/bin/codex-exec-server-service <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec ${quoted_binary} exec-server --listen ws://127.0.0.1:${exec_port}${exec_flags}
EOF
    chmod 0755 /usr/local/bin/codex-exec-server-service
    service_dir=/etc/s6-overlay/s6-rc.d/codex-exec-server
    install -d -m 0755 "${service_dir}/dependencies.d"
    printf 'longrun\n' >"${service_dir}/type"
    touch "${service_dir}/dependencies.d/base"
    cat >"${service_dir}/run" <<EOF
#!/command/with-contenv bash
exec s6-setuidgid ${quoted_user} env HOME=${quoted_home} USER=${quoted_user} /usr/local/bin/codex-exec-server-service
EOF
    chmod 0755 "${service_dir}/run"
    touch /etc/s6-overlay/user-bundles.d/user/contents.d/codex-exec-server
    log "Configured Codex exec-server as ${devcontainer_user} on 127.0.0.1:${exec_port}."
fi

if [ -n "${dns_name}" ]; then
    if [ "${start_app_server}" = true ]; then
        printf -v quoted_user '%q' "${devcontainer_user}"
        printf -v quoted_home '%q' "${user_home}"
        # Keep Codex's private socket unchanged; Caddy uses this same-user bridge.
        cat >/usr/local/bin/codex-app-server-proxy-service <<'PROXY'
#!/usr/bin/env bash
set -euo pipefail
socket="$(realpath -m -- "${CODEX_HOME:-${HOME}/.codex}")/app-server-control/app-server-control.sock"
# Socat's address parser must also preserve commas and quotes in profile paths.
socket="${socket//\\/\\\\}"
socket="${socket//\"/\\\"}"
PROXY
        # shellcheck disable=SC2016
        printf 'exec socat "TCP4-LISTEN:%s,bind=127.0.0.1,reuseaddr,fork" "UNIX-CONNECT:\\\"${socket}\\\""\n' "${app_port}" >>/usr/local/bin/codex-app-server-proxy-service
        chmod 0755 /usr/local/bin/codex-app-server-proxy-service
        service_dir=/etc/s6-overlay/s6-rc.d/codex-app-server-proxy
        install -d -m 0755 "${service_dir}/dependencies.d"
        printf 'longrun\n' >"${service_dir}/type"
        touch "${service_dir}/dependencies.d/codex-cli"
        cat >"${service_dir}/run" <<EOF
#!/command/with-contenv bash
exec s6-setuidgid ${quoted_user} env HOME=${quoted_home} USER=${quoted_user} /usr/local/bin/codex-app-server-proxy-service
EOF
        chmod 0755 "${service_dir}/run"
        touch /etc/s6-overlay/user-bundles.d/user/contents.d/codex-app-server-proxy
        echo "[codex-cli] WARNING: https://${dns_name}/ exposes the app-server without authentication and permits command execution. Exec-server authentication does not protect this route; restrict access through Caddy or the network." >&2
    fi
    caddy_fragment=/etc/caddy/conf.d/codex-cli.caddy
    printf '%s {\n    @exec path /exec-server /exec-server/*\n    handle @exec {\n' "${dns_name}" >"${caddy_fragment}"
    if [ "${exec_server}" != false ]; then
        printf '        rewrite * /\n        reverse_proxy 127.0.0.1:%s\n' "${exec_port}" >>"${caddy_fragment}"
        has_exec_auth=false
        for argument in "${exec_args[@]}"; do
            case "${argument}" in --ws-auth|--ws-auth=*) has_exec_auth=true ;; esac
        done
        if [ "${has_exec_auth}" = false ]; then
            echo "[codex-cli] WARNING: https://${dns_name}/exec-server exposes unauthenticated command execution. Configure execServer authentication or restrict access through Caddy or the network." >&2
        fi
    else
        printf '        respond "Exec-server is disabled" 404\n' >>"${caddy_fragment}"
    fi
    printf '    }\n    handle {\n' >>"${caddy_fragment}"
    if [ "${start_app_server}" = true ]; then
        # Match the native TCP listener's rejection of browser Origin headers.
        printf '        @browser_origin header Origin *\n        respond @browser_origin "Origin headers are not supported" 403\n        reverse_proxy 127.0.0.1:%s\n' "${app_port}" >>"${caddy_fragment}"
    else
        printf '        respond "App-server is disabled" 404\n' >>"${caddy_fragment}"
    fi
    printf '    }\n}\n' >>"${caddy_fragment}"
    chmod 0644 "${caddy_fragment}"
    printf '%s\n' "${dns_name}" >/etc/caddy/required-hosts.d/codex-cli.host
    chmod 0644 /etc/caddy/required-hosts.d/codex-cli.host
    log "Configured Codex services behind Caddy at https://${dns_name}."
fi
