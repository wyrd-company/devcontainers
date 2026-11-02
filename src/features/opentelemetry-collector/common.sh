#!/usr/bin/env bash

# Globals upstream_binary, architecture, and distribution are set by install.sh.
# shellcheck disable=SC2154

# Release selection is separate from installation so both lookup paths can be checked.
resolve_latest_version() {
    local tag_url version archive_url status
    tag_url="$(curl --fail --location --silent --show-error --retry 3 \
        --output /dev/null --write-out '%{url_effective}' \
        https://github.com/open-telemetry/opentelemetry-collector-releases/releases/latest)" \
        || err "Unable to resolve the latest OpenTelemetry Collector release page."

    [[ "$tag_url" =~ ^https://github\.com/open-telemetry/opentelemetry-collector-releases/releases/tag/v([0-9]+\.[0-9]+\.[0-9]+)$ ]] \
        || err "The latest release page did not redirect to a stable Collector version."
    version="${BASH_REMATCH[1]}"
    archive_url="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${version}/${upstream_binary}_${version}_linux_${architecture}.tar.gz"
    status="$(curl --head --location --silent --show-error --retry 3 \
        --output /dev/null --write-out '%{http_code}' "$archive_url")" \
        || err "Unable to check the latest ${distribution} archive for Linux ${architecture}."

    case "$status" in
        200) printf '%s\n' "$version" ;;
        404)
            log "Latest release ${version} has no ${distribution} archive for Linux ${architecture}; searching older releases through the GitHub API." >&2
            resolve_latest_version_from_api
            ;;
        *) err "Unable to check the latest ${distribution} archive for Linux ${architecture}: HTTP ${status}." ;;
    esac
}

resolve_latest_version_from_api() {
    local releases_json version page=1
    local -a curl_args=(
        --fail
        --location
        --silent
        --show-error
        --retry 3
        -H "Accept: application/vnd.github+json"
    )

    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi

    while :; do
        releases_json="$(curl "${curl_args[@]}" \
            "https://api.github.com/repos/open-telemetry/opentelemetry-collector-releases/releases?per_page=20&page=${page}")" \
            || err "Unable to query OpenTelemetry Collector releases. Set 'version' to a published version and retry."

        version="$(printf '%s\n' "${releases_json}" | jq -r \
            --arg binary "${upstream_binary}" \
            --arg architecture "${architecture}" '
                [
                    .[]
                    | select(.draft == false and .prerelease == false)
                    | . as $release
                    | ($release.tag_name | ltrimstr("v")) as $version
                    | select(any(
                        $release.assets[]?;
                        .name == ($binary + "_" + $version + "_linux_" + $architecture + ".tar.gz")
                      ))
                    | $version
                ]
                | first // empty
            ')"

        if [ -n "${version}" ]; then
            echo "${version}"
            return
        fi
        [ "$(printf '%s\n' "${releases_json}" | jq 'length')" -gt 0 ] || break
        page=$((page + 1))
    done

    err "No stable OpenTelemetry Collector release contains ${distribution} for Linux ${architecture}."
}
