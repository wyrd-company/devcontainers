#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

require_root
check_debian_family
ensure_s6_overlay
ensure_apt_packages ca-certificates

[[ "${VERSION}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || err "version must be an npm version or dist-tag."

[[ "${PORT}" =~ ^[0-9]+$ ]] || err "port must be an integer between 1 and 65535."
[ "${#PORT}" -le 5 ] || err "port must be an integer between 1 and 65535."
((10#${PORT} >= 1 && 10#${PORT} <= 65535)) || err "port must be an integer between 1 and 65535."

if [ -n "${DNSNAME}" ]; then
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
    "${install_prefix}" "${install_prefix}/bin" "${install_prefix}/lib"

package_spec="@bitkyc08/opencodex@${VERSION}"
log "Installing ${package_spec} for ${service_user} under ${install_prefix}"
run_as_user "${service_user}" env \
    HOME="${service_home}" \
    PATH="${node_bin_dir}:${install_prefix}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    npm install --global --prefix "${install_prefix}" \
    --allow-scripts=bun --no-audit --no-fund "${package_spec}"

ocx_binary="${install_prefix}/bin/ocx"
[ -x "${ocx_binary}" ] || err "OpenCodex was not installed at ${ocx_binary}."

gate_dir=/run/opencodex
gate_file="${gate_dir}/paused"
install -d -m 0755 -o "${service_user}" -g "${service_group}" "${gate_dir}"

printf -v quoted_user '%q' "${service_user}"
printf -v quoted_group '%q' "${service_group}"
printf -v quoted_home '%q' "${service_home}"
printf -v quoted_ocx '%q' "${ocx_binary}"
printf -v quoted_port '%q' "${PORT}"
printf -v quoted_gate_dir '%q' "${gate_dir}"
printf -v quoted_gate '%q' "${gate_file}"

# System-wide `ocx` entry point. It holds the supervised proxy down while `ocx update`
# replaces the package so s6 does not restart the old code mid-update.
cat >/usr/local/bin/ocx <<EOF2
#!/usr/bin/env bash
set -euo pipefail

ocx=${quoted_ocx}
gate=${quoted_gate}
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
    if touch "\${gate}" 2>/dev/null; then
        trap 'rm -f "\${gate}"' EXIT
    else
        echo "[ocx] Unable to write \${gate}; the supervised proxy is not held during this update." >&2
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

if [ -e "\${gate}" ]; then
    echo "[opencodex-service] Paused while \${gate} exists."
    while [ -e "\${gate}" ]; do
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
install -d -m 0755 -o ${quoted_user} -g ${quoted_group} ${quoted_gate_dir}
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

installed_version="$(run_as_user "${service_user}" env HOME="${service_home}" PATH="${node_bin_dir}:${PATH}" "${ocx_binary}" --version)"
installed_version="${installed_version#opencodex }"
if [[ "${VERSION}" =~ ^[0-9] ]] && [ "${installed_version}" != "${VERSION}" ]; then
    err "OpenCodex ${VERSION} was requested, but ${installed_version} was installed."
fi
log "Installed OpenCodex ${installed_version} as an s6 service running as ${service_user}."
