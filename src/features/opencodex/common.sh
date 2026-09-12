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

check_debian_family() {
    local feature_version="${VERSION-}"

    [ -r /etc/os-release ] || err "Unable to detect Linux distribution."
    # shellcheck disable=SC1091
    . /etc/os-release

    case "${ID:-} ${ID_LIKE:-}" in
        *debian*|*ubuntu*)
            VERSION="${feature_version}"
            ;;
        *)
            VERSION="${feature_version}"
            err "This Feature currently supports Debian/Ubuntu-based images."
            ;;
    esac
}

ensure_s6_overlay() {
    [ -x /init ] || err "s6-overlay 3 is required, but /init is missing."
    [ -x /command/s6-rc ] || err "s6-overlay 3 is required, but s6-rc is missing."
    [ -d /etc/s6-overlay/s6-rc.d ] || err "s6-overlay 3 service definitions are unavailable."
    [ -d /etc/s6-overlay/user-bundles.d/user/contents.d ] || err "s6-overlay 3 user bundle is unavailable."
}

ensure_apt_packages() {
    if [ "${APT_UPDATED}" -eq 0 ]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        APT_UPDATED=1
    fi
    apt-get install -y --no-install-recommends "$@"
}

pick_service_user() {
    local requested="${1:-automatic}"
    local candidate

    if [ -n "${requested}" ] && [ "${requested}" != "automatic" ]; then
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
