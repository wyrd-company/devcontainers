#!/usr/bin/env bash
# relationships: {references: ../../../../AGENTS.md}
set -euo pipefail
log() { echo "[${FEATURE}] $*"; }
err() { log "ERROR: $*" >&2; exit 1; }
preflight() {
    [ "$(id -u)" -eq 0 ] || err "Run this installer as root."
    local ID ID_LIKE VERSION
    # shellcheck disable=SC1091
    . /etc/os-release
    case " ${ID} ${ID_LIKE:-} " in *debian*|*ubuntu*) ;; *) err "Debian or Ubuntu is required." ;; esac
    case "$(dpkg --print-architecture)" in
        amd64) sdk_arch=x64 ;;
        arm64) sdk_arch=arm64 ;;
        *) err "Only amd64 and arm64 are supported." ;;
    esac
    sdk_user=root
    for candidate in "${_REMOTE_USER:-}" "${_CONTAINER_USER:-}" vscode root; do
        if [ -n "$candidate" ] && id -u "$candidate" >/dev/null 2>&1; then sdk_user="$candidate"; break; fi
    done
    sdk_home="$(getent passwd "$sdk_user" | cut -d: -f6)"
    sdk_group="$(id -gn "$sdk_user")"
    [ -n "$sdk_home" ] || err "Cannot resolve the user's home."
}
validate_version() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]] || err "Expected latest or a full SDK version."
}
as_user() { runuser -u "$sdk_user" -- env HOME="$sdk_home" "$@"; }
packages() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends "$@"
    rm -rf /var/lib/apt/lists/*
}
link_tool() {
    install -d -m 0755 -o "$sdk_user" -g "$sdk_group" "$sdk_home/.local" "$sdk_home/.local/bin"
    ln -sf "$2" "$sdk_home/.local/bin/$1"
    chown -h "$sdk_user:$sdk_group" "$sdk_home/.local/bin/$1"
    ln -sf "$sdk_home/.local/bin/$1" "/usr/local/bin/$1"
}
