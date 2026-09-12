#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

require_root
check_debian_family
ensure_s6_overlay
ensure_apt_packages ca-certificates

[[ "${VERSION}" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || err "version must be an npm version or dist-tag."
case "${MODE}" in
    client|standalone) ;;
    *) err "mode must be either 'client' or 'standalone'." ;;
esac

if [ "${MODE}" = standalone ]; then
    [[ "${PORT}" =~ ^[0-9]+$ ]] || err "port must be an integer between 1 and 65535."
    [ "${#PORT}" -le 5 ] || err "port must be an integer between 1 and 65535."
    ((10#${PORT} >= 1 && 10#${PORT} <= 65535)) || err "port must be an integer between 1 and 65535."
fi

if [ -n "${DNSNAME}" ]; then
    [ "${MODE}" = standalone ] || err "dnsName requires mode=standalone."
    [ "${#DNSNAME}" -le 253 ] || err "dnsName exceeds the 253-character DNS limit."
    IFS=. read -r -a dns_labels <<<"${DNSNAME}"
    [ "${#dns_labels[@]}" -ge 2 ] || err "dnsName must be a fully qualified DNS name."
    for label in "${dns_labels[@]}"; do
        [[ "${label}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] \
            || err "dnsName contains an invalid DNS label: '${label}'."
    done
    [ -d /etc/caddy/conf.d ] \
        || err "dnsName requires the Caddy Feature and its /etc/caddy/conf.d directory."
    [ -d /etc/caddy/required-hosts.d ] \
        || err "dnsName requires a Caddy Feature version with DNS readiness support."
fi

command -v npm >/dev/null 2>&1 || err "npm is required. Install the Node Feature before this Feature."
node_bin_dir="$(dirname "$(command -v node)")"

service_user="$(pick_service_user "${SERVICEUSER}")"
service_group="$(id -gn "${service_user}")"
service_home="$(user_home_dir "${service_user}")"
[ -n "${service_home}" ] || err "Unable to resolve the home directory for ${service_user}."

# The npm prefix is user-owned so `ocx update` can stage and swap the package as the
# service user. OpenCodex state lives in ${HOME}/.opencodex (OPENCODEX_HOME).
install_prefix="${service_home}/.local"
install -d -m 0755 -o "${service_user}" -g "${service_group}" \
    "${service_home}/.opencodex" \
    "${service_home}/.codex" \
    "${install_prefix}" "${install_prefix}/bin" "${install_prefix}/lib"

package_spec="@bitkyc08/opencodex@${VERSION}"
user_path="${node_bin_dir}:${install_prefix}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
resolved_version="$(run_as_user "${service_user}" env HOME="${service_home}" PATH="${user_path}" \
    NPM_CONFIG_UPDATE_NOTIFIER=false npm view "${package_spec}" version 2>/dev/null | tail -n 1)"
resolved_version="${resolved_version##* }"
resolved_version="${resolved_version//\'/}"
[ -n "${resolved_version}" ] || err "Unable to resolve ${package_spec} on the npm registry."
log "Installing ${package_spec} (${resolved_version}) for ${service_user} under ${install_prefix}"
run_as_user "${service_user}" env \
    HOME="${service_home}" \
    PATH="${user_path}" \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    npm install --global --prefix "${install_prefix}" \
    --allow-scripts=bun --no-audit --no-fund "${package_spec}"

ocx_binary="${install_prefix}/bin/ocx"
[ -x "${ocx_binary}" ] || err "OpenCodex was not installed at ${ocx_binary}."

installed_version="$(run_as_user "${service_user}" env HOME="${service_home}" PATH="${node_bin_dir}:${PATH}" "${ocx_binary}" --version)"
installed_version="${installed_version#opencodex }"
[ "${installed_version}" = "${resolved_version}" ] \
    || err "OpenCodex ${VERSION} resolved to ${resolved_version}, but ${installed_version} was installed."

printf -v quoted_user '%q' "${service_user}"
printf -v quoted_home '%q' "${service_home}"
printf -v quoted_ocx '%q' "${ocx_binary}"
printf -v quoted_node '%q' "$(command -v node)"

if [ "${MODE}" = client ]; then
    cat >/usr/local/bin/ocx <<EOF2
#!/usr/bin/env bash
set -euo pipefail
ocx=${quoted_ocx}
export HOME=${quoted_home}
exec "\${ocx}" "\$@"
EOF2
    chmod 0755 /usr/local/bin/ocx
    ln -sfn ocx /usr/local/bin/opencodex

    cat >/usr/local/bin/opencodex-client-sync <<EOF2
#!/usr/bin/env bash
set -u

ocx=${quoted_ocx}
export HOME=${quoted_home}

if ! status="\$("\${ocx}" connect status --json 2>/dev/null)"; then
    echo "[opencodex-client-sync] Unable to inspect Remote Hub client state; startup continues without synchronization." >&2
    exit 0
fi

if ! connection="\$(printf '%s' "\${status}" | ${quoted_node} -e '
let raw = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", chunk => raw += chunk);
process.stdin.on("end", () => {
  try {
    const value = JSON.parse(raw);
    if (typeof value.state !== "string" || typeof value.token !== "string") process.exit(1);
    process.stdout.write(value.state + ":" + value.token);
  } catch { process.exit(1); }
});
')"; then
    echo "[opencodex-client-sync] Remote Hub client status was not valid JSON; startup continues without synchronization." >&2
    exit 0
fi

case "\${connection}" in
    connected:owned)
        if ! "\${ocx}" sync; then
            echo "[opencodex-client-sync] Remote Hub synchronization failed; startup continues with retained client state." >&2
        fi
        ;;
    disconnected:*)
        echo "[opencodex-client-sync] Enrollment required: run 'ocx connect' with transient authority from the hub."
        ;;
    *)
        echo "[opencodex-client-sync] Remote Hub client state is \${connection}; run 'ocx connect status' to repair it." >&2
        ;;
esac
exit 0
EOF2
    chmod 0755 /usr/local/bin/opencodex-client-sync

    sync_dir=/etc/s6-overlay/s6-rc.d/opencodex-client-sync
    install -d -m 0755 "${sync_dir}"
    printf 'oneshot\n' >"${sync_dir}/type"
    cat >"${sync_dir}/up" <<EOF2
#!/command/with-contenv bash
exec s6-setuidgid ${quoted_user} /usr/local/bin/opencodex-client-sync
EOF2
    chmod 0755 "${sync_dir}/up"
    touch /etc/s6-overlay/user-bundles.d/user/contents.d/opencodex-client-sync

    log "Installed OpenCodex ${installed_version} in client mode for ${service_user}."
    exit 0
fi

# /run/opencodex/paused is the operator's manual hold. /run/opencodex/holds/<pid> files
# are per-process holds owned by a running `ocx update`; the launcher ignores holds
# whose process is gone. update.lock serializes updates.
gate_dir=/run/opencodex
gate_file="${gate_dir}/paused"
holds_dir="${gate_dir}/holds"
lock_file="${gate_dir}/update.lock"
install -d -m 0755 -o "${service_user}" -g "${service_group}" "${gate_dir}" "${holds_dir}"

printf -v quoted_group '%q' "${service_group}"
printf -v quoted_port '%q' "${PORT}"
printf -v quoted_gate_dir '%q' "${gate_dir}"
printf -v quoted_gate '%q' "${gate_file}"
printf -v quoted_holds '%q' "${holds_dir}"
printf -v quoted_lock '%q' "${lock_file}"

# System-wide `ocx` entry point. It holds the supervised proxy down while `ocx update`
# replaces the package so s6 does not restart the old code mid-update.
cat >/usr/local/bin/ocx <<EOF2
#!/usr/bin/env bash
set -euo pipefail

ocx=${quoted_ocx}
holds=${quoted_holds}
lock=${quoted_lock}
hold=0

if [ "\${1-}" = update ]; then
    hold=1
    for arg in "\${@:2}"; do
        case "\${arg}" in
            --help|-h|help) hold=0 ;;
        esac
    done
fi

if [ "\${hold}" -eq 1 ]; then
    if mkdir -p "\${holds}" 2>/dev/null && exec 9>"\${lock}" 2>/dev/null; then
        if ! flock -n 9; then
            echo "[ocx] Another ocx update holds \${lock}; wait for it to finish." >&2
            exit 1
        fi
        hold_file="\${holds}/\$\$"
        printf '%s\\n' "\$\$" >"\${hold_file}"
        trap 'rm -f "\${hold_file}"' EXIT
    else
        echo "[ocx] Unable to write \${holds}; the supervised proxy is not held during this update." >&2
    fi
fi

status=0
"\${ocx}" "\$@" || status=\$?
exit "\${status}"
EOF2
chmod 0755 /usr/local/bin/ocx
ln -sfn ocx /usr/local/bin/opencodex

cat >/usr/local/bin/opencodex-service <<EOF2
#!/usr/bin/env bash
set -euo pipefail

export HOME=${quoted_home}
export USER=${quoted_user}
export OCX_SERVICE=1

port=${quoted_port}
gate=${quoted_gate}
holds=${quoted_holds}

held() {
    local hold_file owner
    [ ! -e "\${gate}" ] || return 0
    for hold_file in "\${holds}"/*; do
        [ -f "\${hold_file}" ] || continue
        owner="\$(cat "\${hold_file}" 2>/dev/null || true)"
        if [[ "\${owner}" =~ ^[0-9]+$ ]] && [ -d "/proc/\${owner}" ]; then
            return 0
        fi
        rm -f "\${hold_file}"
    done
    return 1
}

if held; then
    echo "[opencodex-service] Paused while \${gate} or a live hold in \${holds} exists."
    while held; do
        sleep 1
    done
    echo "[opencodex-service] Resuming."
fi

exec ${quoted_ocx} start --port "\${port}" "\$@"
EOF2
chmod 0755 /usr/local/bin/opencodex-service

service_dir=/etc/s6-overlay/s6-rc.d/opencodex
install -d -m 0755 "${service_dir}/dependencies.d"
printf 'longrun\n' >"${service_dir}/type"
touch "${service_dir}/dependencies.d/base"

cat >"${service_dir}/run" <<EOF2
#!/command/with-contenv bash
install -d -m 0755 -o ${quoted_user} -g ${quoted_group} ${quoted_gate_dir} ${quoted_holds}
exec s6-setuidgid ${quoted_user} /usr/local/bin/opencodex-service
EOF2
chmod 0755 "${service_dir}/run"
touch /etc/s6-overlay/user-bundles.d/user/contents.d/opencodex

if [ -n "${DNSNAME}" ]; then
    # OpenCodex admits management requests only with a loopback Host and a loopback (or
    # absent) Origin. Caddy presents the upstream loopback Host and rewrites the
    # dashboard's own Origin; every other Origin passes through and is refused upstream.
    cat >/etc/caddy/conf.d/opencodex.caddy <<EOF2
${DNSNAME} {
    @dashboard_origin header Origin https://${DNSNAME}
    request_header @dashboard_origin Origin http://127.0.0.1:${PORT}
    reverse_proxy 127.0.0.1:${PORT} {
        header_up Host {upstream_hostport}
    }
}
EOF2
    chmod 0644 /etc/caddy/conf.d/opencodex.caddy
    printf '%s\n' "${DNSNAME}" >/etc/caddy/required-hosts.d/opencodex.host
    chmod 0644 /etc/caddy/required-hosts.d/opencodex.host
    log "Configured https://${DNSNAME} to proxy to the OpenCodex dashboard on 127.0.0.1:${PORT}."
fi

log "Installed OpenCodex ${installed_version} as an s6 service running as ${service_user}."
