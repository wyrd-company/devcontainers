#!/usr/bin/env bash

set -euo pipefail

APT_UPDATED=0

log() {
    echo "[$(basename "$0")] $*"
}

err() {
    echo "[$(basename "$0")] ERROR: $*" >&2
    exit 1
}

require_root() {
    [ "$(id -u)" -eq 0 ] || err "This Feature must run as root."
}

ensure_apt_packages() {
    if [ "${APT_UPDATED}" -eq 0 ]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        APT_UPDATED=1
    fi
    apt-get install -y --no-install-recommends "$@"
}

pick_devcontainer_user() {
    local candidate

    for candidate in "${_REMOTE_USER:-}" "${_CONTAINER_USER:-}" vscode root; do
        if [ -n "${candidate}" ] && id -u "${candidate}" >/dev/null 2>&1; then
            echo "${candidate}"
            return
        fi
    done

    err "Unable to resolve the Dev Container user."
}

user_home_dir() {
    getent passwd "$1" | cut -d: -f6
}

run_as_user() {
    local username="$1"
    shift

    if [ "${username}" = root ]; then
        "$@"
    else
        runuser --user "${username}" -- "$@"
    fi
}
