#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

require_root
check_debian_family
ensure_s6_overlay
ensure_apt_packages ca-certificates curl python3 tar

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

if [ -n "${RELEASEBASEURL}" ]; then
    [[ "${RELEASEBASEURL}" =~ ^https?:// ]] || err "releaseBaseUrl must be an http(s) URL."
fi

case "$(dpkg --print-architecture)" in
    amd64) arch=x64 ;;
    arm64) arch=arm64 ;;
    *) err "T3 Code release archives support amd64 and arm64 only." ;;
esac

service_user="$(pick_service_user "${SERVICEUSER}")"
service_home="$(user_home_dir "${service_user}")"
[ -n "${service_home}" ] || err "Unable to resolve the home directory for ${service_user}."

lib_dir=/usr/local/lib/t3code-server
install -d -m 0755 "${lib_dir}"
install -m 0755 "$(dirname "$0")/t3code-runtime" "${lib_dir}/t3code-runtime"
install -m 0755 "$(dirname "$0")/resolve-package-source.py" "${lib_dir}/resolve-package-source.py"
install -m 0755 "$(dirname "$0")/t3code-server-update" /usr/local/bin/t3code-server-update

mapfile -t resolution < <(python3 "${lib_dir}/resolve-package-source.py" "${PACKAGESOURCE}" "${VERSION}" "${arch}")
[ "${#resolution[@]}" -eq 5 ] || err "Unable to resolve the T3 Code package source."
package_kind="${resolution[0]}"
package_source="${resolution[1]}"
resolved_version="${resolution[2]}"
checksums_url="${resolution[3]}"
release_base_url="${RELEASEBASEURL:-${resolution[4]}}"

# The runtime tool and the update command read this file; the service wrapper
# exports the server settings from it.
cat >"${lib_dir}/config.env" <<EOF
T3CODE_SERVER_USER=$(printf '%q' "${service_user}")
T3CODE_SERVER_HOME=$(printf '%q' "${service_home}")
T3CODE_SERVER_ARCH=$(printf '%q' "${arch}")
T3CODE_SERVER_PACKAGE_SOURCE=$(printf '%q' "${PACKAGESOURCE}")
T3CODE_SERVER_RELEASE_BASE_URL=$(printf '%q' "${release_base_url}")
T3CODE_SERVER_PORT=$(printf '%q' "${PORT}")
T3CODE_SERVER_HOST=$(printf '%q' "${HOST}")
T3CODE_SERVER_MODE=$(printf '%q' "${SERVEMODE}")
EOF
chmod 0644 "${lib_dir}/config.env"

install -d -m 0755 -o "${service_user}" -g "$(id -gn "${service_user}")" "${service_home}/.t3"

case "${package_kind}" in
    archive)
        log "Installing T3 Code ${resolved_version} from ${package_source}"
        "${lib_dir}/t3code-runtime" install-archive "${resolved_version}" "${package_source}" "${checksums_url}"
        ;;
    npm)
        log "Installing ${package_source} with npm"
        command -v npm >/dev/null 2>&1 || err "npm is required to install ${package_source}."
        ensure_apt_packages build-essential
        installed="$("${lib_dir}/t3code-runtime" install-npm "${package_source}")"
        resolved_version="${resolved_version:-${installed}}"
        ;;
    *)
        err "Unknown package kind '${package_kind}'."
        ;;
esac
"${lib_dir}/t3code-runtime" activate "${resolved_version}" --force

# `t3` on PATH always runs the version the service is selected to run.
cat >/usr/local/bin/t3 <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "\$(${lib_dir@Q}/t3code-runtime active-entry)" "\$@"
EOF
chmod 0755 /usr/local/bin/t3

printf -v quoted_home '%q' "${service_home}"
printf -v quoted_port '%q' "${PORT}"
printf -v quoted_host '%q' "${HOST}"
printf -v quoted_mode '%q' "${SERVEMODE}"
printf -v quoted_release_base '%q' "${release_base_url}"

cat >/usr/local/bin/t3code-server <<EOF
#!/usr/bin/env bash
set -euo pipefail

export HOME=${quoted_home}
export T3CODE_HOME="\${HOME}/.t3"
export T3CODE_NO_BROWSER=1

default_port=${quoted_port}
default_host=${quoted_host}
default_mode=${quoted_mode}
default_release_base=${quoted_release_base}
export T3CODE_PORT="\${T3CODE_PORT:-\${default_port}}"
export T3CODE_HOST="\${T3CODE_HOST:-\${default_host}}"
mode="\${T3CODE_MODE:-\${default_mode}}"
if [ -n "\${mode}" ]; then
    export T3CODE_MODE="\${mode}"
fi
release_base="\${T3CODE_RELEASE_BASE_URL:-\${default_release_base}}"
if [ -n "\${release_base}" ]; then
    export T3CODE_RELEASE_BASE_URL="\${release_base}"
fi

# The launcher of the selected version supervises \`t3 serve\` and applies
# updates requested by clients; a restarted service picks up whichever
# version is selected by then.
exec "\$(${lib_dir@Q}/t3code-runtime active-entry)" __service-launcher "\$@"
EOF
chmod 0755 /usr/local/bin/t3code-server

service_dir=/etc/s6-overlay/s6-rc.d/t3code-server
install -d -m 0755 "${service_dir}/dependencies.d"
printf 'longrun\n' >"${service_dir}/type"
touch "${service_dir}/dependencies.d/base"

printf -v quoted_user '%q' "${service_user}"
cat >"${service_dir}/run" <<EOF
#!/command/with-contenv bash
exec s6-setuidgid ${quoted_user} /usr/local/bin/t3code-server
EOF
chmod 0755 "${service_dir}/run"
touch /etc/s6-overlay/user-bundles.d/user/contents.d/t3code-server

if [ -n "${DNSNAME}" ]; then
    cat >/etc/caddy/conf.d/t3code-server.caddy <<EOF
${DNSNAME} {
    reverse_proxy 127.0.0.1:${PORT}
}
EOF
    chmod 0644 /etc/caddy/conf.d/t3code-server.caddy
    printf '%s\n' "${DNSNAME}" >/etc/caddy/required-hosts.d/t3code-server.host
    chmod 0644 /etc/caddy/required-hosts.d/t3code-server.host
    log "Configured https://${DNSNAME} to proxy to T3 Code on 127.0.0.1:${PORT}."
fi

installed_version="$(run_as_user "${service_user}" env HOME="${service_home}" /usr/local/bin/t3 --version)"
"$(dirname "$0")/verify-version.sh" "${installed_version}" "${resolved_version}"
log "Installed T3 Code ${installed_version}"
