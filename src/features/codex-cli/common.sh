#!/usr/bin/env bash

set -euo pipefail

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

pick_devcontainer_user() {
    local requested="${1:-automatic}"
    local candidate
    if [ "${requested}" != automatic ] && [ "${requested}" != auto ]; then
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
