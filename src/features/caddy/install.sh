#!/usr/bin/env bash

set -euo pipefail

log() {
    echo "[caddy] $*"
}

err() {
    echo "[caddy] ERROR: $*" >&2
    exit 1
}

pick_config_user() {
    local requested="${1:-automatic}"
    local candidate

    if [ -n "${requested}" ] && [ "${requested}" != automatic ] && [ "${requested}" != auto ]; then
        id -u "${requested}" >/dev/null 2>&1 || err "Requested config user '${requested}' does not exist."
        echo "${requested}"
        return
    fi

    for candidate in "${_REMOTE_USER:-}" "${_CONTAINER_USER:-}" vscode root; do
        if [ -n "${candidate}" ] && id -u "${candidate}" >/dev/null 2>&1; then
            echo "${candidate}"
            return
        fi
    done

    err "Unable to resolve a config user."
}

caddy_quote() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "${value}"
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

case "${ACMECA}" in
    *$'\n'*|*$'\r'*|*'{'*|*'}'*) err "acmeCa contains unsupported Caddyfile characters." ;;
esac
case "${ACMECAROOT}" in
    *$'\n'*|*$'\r'*|*'{'*|*'}'*) err "acmeCaRoot contains unsupported Caddyfile characters." ;;
esac

case "$(uname -m)" in
    x86_64|amd64) architecture=amd64 ;;
    arm64|aarch64) architecture=arm64 ;;
    *) err "Unsupported architecture: $(uname -m)." ;;
esac

if [ "${requested_version}" != latest ]; then
    [[ "${requested_version}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]] \
        || err "version must be 'latest' or a semantic version such as '2.11.4'."
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    inotify-tools \
    jq

download_dir="$(mktemp -d)"
trap 'rm -rf "${download_dir}"' EXIT

# Caddy's Cloudsmith apt repository is signed with an expired subkey, so the
# package is installed from the GitHub release and verified against its checksums.
if [ "${requested_version}" = latest ]; then
    log "Resolving the latest stable Caddy release..."
    curl_args=(--fail --location --silent --show-error --retry 3 -H "Accept: application/vnd.github+json")
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi
    normalized_version="$(curl "${curl_args[@]}" \
        https://api.github.com/repos/caddyserver/caddy/releases/latest \
        | jq -r '.tag_name // empty | ltrimstr("v")')" \
        || err "Unable to query Caddy releases. Set 'version' to a published version and retry."
    [ -n "${normalized_version}" ] || err "Unable to resolve the latest Caddy release."
else
    normalized_version="${requested_version#v}"
fi

package_name="caddy_${normalized_version}_linux_${architecture}.deb"
checksums_name="caddy_${normalized_version}_checksums.txt"
release_url="https://github.com/caddyserver/caddy/releases/download/v${normalized_version}"
package="${download_dir}/${package_name}"
checksums_file="${download_dir}/${checksums_name}"

log "Downloading Caddy ${normalized_version} for Linux ${architecture}."
curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
    --output "${checksums_file}" "${release_url}/${checksums_name}"
curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
    --output "${package}" "${release_url}/${package_name}"

expected_checksum="$(awk -v package="${package_name}" '$2 == package { print $1 }' "${checksums_file}")"
[[ "${expected_checksum}" =~ ^[0-9a-fA-F]{128}$ ]] \
    || err "No valid checksum was published for ${package_name}."
printf '%s  %s\n' "${expected_checksum}" "${package}" | sha512sum --check --status \
    || err "Checksum verification failed for ${package_name}."

apt-get install -y --no-install-recommends "${package}"

command -v caddy >/dev/null 2>&1 || err "Caddy installation failed."
case "$(caddy version)" in
    "v${normalized_version}"|"v${normalized_version} "*) ;;
    *) err "Installed Caddy reports '$(caddy version)', expected v${normalized_version}." ;;
esac
id -u caddy >/dev/null 2>&1 || err "The Caddy package did not create its service user."

config_user="$(pick_config_user "${CONFIGUSER}")"
getent group caddy-config >/dev/null 2>&1 || groupadd --system caddy-config
usermod -aG caddy-config caddy
if [ "${config_user}" != root ]; then
    usermod -aG caddy-config "${config_user}"
fi

install -d -m 0750 -o caddy -g caddy /var/lib/caddy /run/caddy
install -d -m 0755 -o root -g root /etc/caddy
install -d -m 2775 -o root -g caddy-config /etc/caddy/conf.d
install -d -m 2775 -o root -g caddy-config /etc/caddy/required-hosts.d

{
    echo '{'
    echo '    admin unix//run/caddy/admin.sock'
    if [ -n "${ACMECA}" ]; then
        printf '    acme_ca %s\n' "$(caddy_quote "${ACMECA}")"
    fi
    if [ -n "${ACMECAROOT}" ]; then
        printf '    acme_ca_root %s\n' "$(caddy_quote "${ACMECAROOT}")"
    fi
    echo '}'
    echo
    echo 'import /etc/caddy/conf.d/*.caddy'
} >/etc/caddy/Caddyfile
chmod 0644 /etc/caddy/Caddyfile

cat >/usr/local/bin/caddy-wait-for-dns <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

directory=/etc/caddy/required-hosts.d

while :; do
    unresolved=()

    shopt -s nullglob
    files=("${directory}"/*.host)
    shopt -u nullglob

    for file in "${files[@]}"; do
        while IFS= read -r hostname || [ -n "${hostname}" ]; do
            hostname="${hostname%%#*}"
            hostname="${hostname//[[:space:]]/}"
            [ -n "${hostname}" ] || continue

            if ! getent ahosts "${hostname}" >/dev/null 2>&1; then
                unresolved+=("${hostname}")
            fi
        done <"${file}"
    done

    if [ "${#unresolved[@]}" -eq 0 ]; then
        exit 0
    fi

    echo "[caddy-wait-for-dns] Waiting for DNS: ${unresolved[*]}" >&2
    sleep 1
done
EOF
chmod 0755 /usr/local/bin/caddy-wait-for-dns

cat >/usr/local/bin/caddy-reload <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

config=/etc/caddy/Caddyfile
admin=unix//run/caddy/admin.sock

caddy validate --config "${config}" --adapter caddyfile
/usr/local/bin/caddy-wait-for-dns
caddy reload --config "${config}" --adapter caddyfile --address "${admin}"
EOF
chmod 0755 /usr/local/bin/caddy-reload

cat >/usr/local/bin/caddy-watch-config <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

directory=/etc/caddy/conf.d

while :; do
    inotifywait --quiet \
        --event close_write,create,delete,moved_to,moved_from \
        "${directory}" >/dev/null 2>&1

    sleep 0.2
    while inotifywait --quiet --timeout 1 \
        --event close_write,create,delete,moved_to,moved_from \
        "${directory}" >/dev/null 2>&1; do
        :
    done

    if ! /usr/local/bin/caddy-reload; then
        echo "[caddy-watch-config] Configuration reload failed; the active configuration was preserved." >&2
    fi
done
EOF
chmod 0755 /usr/local/bin/caddy-watch-config

caddy_service=/etc/s6-overlay/s6-rc.d/caddy
install -d -m 0755 "${caddy_service}/dependencies.d"
printf 'longrun\n' >"${caddy_service}/type"
touch "${caddy_service}/dependencies.d/base"
cat >"${caddy_service}/run" <<'EOF'
#!/command/with-contenv bash
install -d -m 0750 -o caddy -g caddy /run/caddy
/usr/local/bin/caddy-wait-for-dns
exec s6-setuidgid caddy env HOME=/var/lib/caddy XDG_DATA_HOME=/var/lib/caddy/.local/share XDG_CONFIG_HOME=/var/lib/caddy/.config caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
EOF
chmod 0755 "${caddy_service}/run"

watcher_service=/etc/s6-overlay/s6-rc.d/caddy-config-watcher
install -d -m 0755 "${watcher_service}/dependencies.d"
printf 'longrun\n' >"${watcher_service}/type"
touch "${watcher_service}/dependencies.d/caddy"
cat >"${watcher_service}/run" <<'EOF'
#!/command/with-contenv bash
while [ ! -S /run/caddy/admin.sock ]; do
    sleep 0.1
done
exec s6-setuidgid caddy /usr/local/bin/caddy-watch-config
EOF
chmod 0755 "${watcher_service}/run"

touch /etc/s6-overlay/user-bundles.d/user/contents.d/caddy
touch /etc/s6-overlay/user-bundles.d/user/contents.d/caddy-config-watcher

caddy fmt --overwrite /etc/caddy/Caddyfile
# Runtime mounts may supply acmeCaRoot after Feature installation, so syntax is
# adapted here without provisioning the configured issuer.
caddy adapt --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null
rm -rf /var/lib/apt/lists/*
log "Installed $(caddy version) with writable fragments for ${config_user}."
