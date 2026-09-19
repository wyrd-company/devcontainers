#!/usr/bin/env bash

set -euo pipefail

log() {
    echo "[opentelemetry-collector] $*"
}

err() {
    echo "[opentelemetry-collector] ERROR: $*" >&2
    exit 1
}

pick_service_user() {
    local requested="${1:-automatic}"
    local candidate

    if [ -n "${requested}" ] && [ "${requested}" != automatic ] && [ "${requested}" != auto ]; then
        id -u "${requested}" >/dev/null 2>&1 \
            || err "Requested service user '${requested}' does not exist."
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

resolve_latest_version() {
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
            "https://api.github.com/repos/open-telemetry/opentelemetry-collector-releases/releases?per_page=100&page=${page}")" \
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

[ "$(id -u)" -eq 0 ] || err "This Feature must run as root."
[ -r /etc/os-release ] || err "Unable to detect Linux distribution."

requested_version="${VERSION:-latest}"
distribution="${DISTRIBUTION:-core}"
service_user_request="${SERVICEUSER:-automatic}"

# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-} ${ID_LIKE:-}" in
    *debian*|*ubuntu*) ;;
    *) err "This Feature currently supports Debian/Ubuntu-based images." ;;
esac

for required_path in /init /command/s6-rc /etc/s6-overlay/s6-rc.d /etc/s6-overlay/user-bundles.d/user/contents.d; do
    [ -e "${required_path}" ] \
        || err "This Feature requires an s6-overlay 3 image with /init as PID 1."
done

case "${distribution}" in
    core) upstream_binary=otelcol ;;
    contrib) upstream_binary=otelcol-contrib ;;
    *) err "distribution must be 'core' or 'contrib'." ;;
esac

case "$(uname -m)" in
    x86_64|amd64) architecture=amd64 ;;
    arm64|aarch64) architecture=arm64 ;;
    *) err "Unsupported architecture: $(uname -m)." ;;
esac

service_user="$(pick_service_user "${service_user_request}")"
service_home="$(getent passwd "${service_user}" | cut -d: -f6)"
[ -n "${service_home}" ] || err "Unable to resolve the home directory for ${service_user}."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends ca-certificates curl jq

download_dir="$(mktemp -d)"
trap 'rm -rf "${download_dir}"' EXIT

if [ "${requested_version}" = latest ]; then
    log "Resolving the latest stable ${distribution} release for Linux ${architecture}..."
    normalized_version="$(resolve_latest_version)"
else
    [[ "${requested_version}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]] \
        || err "version must be 'latest' or a semantic version such as '0.160.0'."
    normalized_version="${requested_version#v}"
fi

archive_name="${upstream_binary}_${normalized_version}_linux_${architecture}.tar.gz"
release_url="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${normalized_version}"
archive="${download_dir}/${archive_name}"
checksum_file="${archive}.sha256"

log "Downloading ${upstream_binary} ${normalized_version} for Linux ${architecture}."
curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
    --output "${archive}" "${release_url}/${archive_name}"
curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
    --output "${checksum_file}" "${release_url}/${archive_name}.sha256"

expected_checksum="$(tr -d '[:space:]' <"${checksum_file}")"
[[ "${expected_checksum}" =~ ^[0-9a-fA-F]{64}$ ]] \
    || err "Upstream did not publish a valid SHA256 checksum for ${archive_name}."
printf '%s  %s\n' "${expected_checksum}" "${archive}" | sha256sum --check --status \
    || err "Checksum verification failed for ${archive_name}."

extract_dir="${download_dir}/extract"
install -d -m 0755 "${extract_dir}"
tar -xzf "${archive}" -C "${extract_dir}"
[ -x "${extract_dir}/${upstream_binary}" ] \
    || err "The release archive did not contain ${upstream_binary}."
install -m 0755 "${extract_dir}/${upstream_binary}" "/usr/local/bin/${upstream_binary}"
ln -sfn "/usr/local/bin/${upstream_binary}" /usr/local/bin/opentelemetry-collector

config_dir=/etc/opentelemetry-collector
config_file="${config_dir}/config.yaml"
install -d -m 0755 -o root -g root "${config_dir}"
cat >"${config_file}" <<'EOF'
extensions:
  health_check:
    endpoint: 127.0.0.1:13133

receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 127.0.0.1:4317
      http:
        endpoint: 127.0.0.1:4318

processors:
  batch:

exporters:
  debug:

service:
  extensions: [health_check]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [debug]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [debug]
    logs:
      receivers: [otlp]
      processors: [batch]
      exporters: [debug]
EOF
chmod 0644 "${config_file}"

printf -v quoted_config '%q' "${config_file}"
cat >/usr/local/bin/opentelemetry-collector-service <<EOF
#!/usr/bin/env bash
set -euo pipefail

exec /usr/local/bin/opentelemetry-collector --config=${quoted_config} "\$@"
EOF
chmod 0755 /usr/local/bin/opentelemetry-collector-service

service_dir=/etc/s6-overlay/s6-rc.d/opentelemetry-collector
install -d -m 0755 "${service_dir}/dependencies.d"
printf 'longrun\n' >"${service_dir}/type"
touch "${service_dir}/dependencies.d/base"
printf -v quoted_user '%q' "${service_user}"
printf -v quoted_home '%q' "${service_home}"
cat >"${service_dir}/run" <<EOF
#!/command/with-contenv bash
exec s6-setuidgid ${quoted_user} env HOME=${quoted_home} USER=${quoted_user} /usr/local/bin/opentelemetry-collector-service
EOF
chmod 0755 "${service_dir}/run"
touch /etc/s6-overlay/user-bundles.d/user/contents.d/opentelemetry-collector

env HOME="${service_home}" USER="${service_user}" \
    /usr/local/bin/opentelemetry-collector validate --config="${config_file}" >/dev/null
rm -rf /var/lib/apt/lists/*
log "Installed ${upstream_binary} ${normalized_version} as an s6 service running as ${service_user}."
