#!/usr/bin/env bash

# Helpers for install.sh, kept separate so they can be checked on their own.

# Prints the API address with `localhost` normalized to 127.0.0.1, or nothing
# when the API is disabled. Rejects anything that is not host:port.
normalize_api_address() {
    local address="$1" host port

    [ -n "${address}" ] || return 0
    host="${address%:*}"
    port="${address##*:}"
    [ "${host}" != "${address}" ] || err "apiAddress must be host:port, such as 127.0.0.1:8686."
    [ "${host}" != localhost ] || host=127.0.0.1
    [[ "${host}" =~ ^([0-9]{1,3}(\.[0-9]{1,3}){3}|\[[0-9A-Fa-f:]+\])$ ]] \
        || err "apiAddress must use an IP address, such as 127.0.0.1:8686."
    [[ "${port}" =~ ^[0-9]{1,5}$ ]] && [ "${port}" -ge 1 ] && [ "${port}" -le 65535 ] \
        || err "apiAddress must end in a port from 1 to 65535."
    printf '%s:%s\n' "${host}" "${port}"
}

# The release page redirect names the latest stable release without using the
# rate-limited GitHub API.
resolve_latest_version() {
    local tag_url
    tag_url="$(curl --fail --location --silent --show-error --retry 3 \
        --output /dev/null --write-out '%{url_effective}' \
        https://github.com/vectordotdev/vector/releases/latest)" \
        || err "Unable to resolve the latest Vector release. Set 'version' to a published version and retry."
    [[ "${tag_url}" =~ ^https://github\.com/vectordotdev/vector/releases/tag/v([0-9]+\.[0-9]+\.[0-9]+)$ ]] \
        || err "The latest release page did not redirect to a stable Vector version."
    printf '%s\n' "${BASH_REMATCH[1]}"
}
