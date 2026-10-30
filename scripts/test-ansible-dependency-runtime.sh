#!/usr/bin/env bash

# Runtime acceptance for the optional Ansible startup dependency.
#
# usage: test-ansible-dependency-runtime.sh FEATURE
#
# The Ansible Feature provides the `ansible-setup` s6-rc oneshot. This test
# stands in for it with a fixture oneshot (test/ansible-dependency) so that the
# service Features are tested without that Feature. For each configuration of
# FEATURE it installs the Feature twice, with and without the fixture, and
# proves that:
#
# - the Feature lists the Ansible Feature in `installsAfter`;
# - with the fixture, exactly the expected services depend on `ansible-setup`,
#   and nothing else in the service definitions differs from the install
#   without it;
# - both service trees compile with s6-rc-compile;
# - the expected services do not start before the oneshot finishes, and never
#   start when it fails (read from the s6-rc transition log, which s6-rc keeps
#   while it holds the service lock, so the live state cannot be queried);
# - without the fixture, the expected services start.

set -euo pipefail

feature="${1:?usage: test-ansible-dependency-runtime.sh FEATURE}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
base_image="${BASE_IMAGE:-$("${repo_root}/scripts/build-base-image.sh" noble)}"
metadata="${repo_root}/src/features/${feature}/devcontainer-feature.json"
s6_rc_dir=/etc/s6-overlay/s6-rc.d
# The sources s6-overlay compiles at boot: the Feature services, the user
# bundle, and the services s6-overlay defines itself.
s6_rc_sources="${s6_rc_dir} /etc/s6-overlay/user-bundles.d /package/admin/s6-overlay/etc/s6-rc/sources"
workspace="$(mktemp -d)"
containers=()

# Pulling the Node.js stage must not depend on the host's credential helper.
DOCKER_CONFIG="${workspace}/docker"
export DOCKER_CONFIG
mkdir -p "${DOCKER_CONFIG}"
printf '{}' >"${DOCKER_CONFIG}/config.json"

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

cleanup() {
    local container
    for container in "${containers[@]}"; do
        docker stop "${container}" >/dev/null 2>&1 || true
        docker rm "${container}" >/dev/null 2>&1 || true
    done
    rm -rf "${workspace}"
}
trap cleanup EXIT

# One line per configuration: name|option overrides|privileged|expected services.
# Overrides are NAME=value pairs in the installer's environment form. A service
# that another service depends on is covered by that dependency.
configurations() {
    case "${feature}" in
        caddy) echo 'default||no|caddy' ;;
        codex-cli) echo 'exec-server|EXECSERVER=true|no|codex-cli codex-exec-server' ;;
        dagu) echo 'default||no|dagu' ;;
        docker-in-docker) echo 'default||yes|docker-in-docker-prepare' ;;
        docker-outside-of-docker) echo 'default||no|docker-outside-of-docker' ;;
        openbao-agent) echo 'default||no|openbao-agent' ;;
        opencodex)
            echo 'client||no|opencodex-client-sync'
            echo 'standalone|MODE=standalone|no|opencodex'
            ;;
        openobserve) echo 'default||no|openobserve' ;;
        opentelemetry-collector) echo 'default||no|opentelemetry-collector' ;;
        sshd) echo 'default||no|sshd' ;;
        t3code-server) echo 'default||no|t3code-server' ;;
        *) fail "No Ansible dependency configuration for ${feature}." ;;
    esac
}

# Every option at its declared default, as the Feature installer reads them.
default_options() {
    jq -r '(.options // {}) | to_entries[] | "\(.key | ascii_upcase)=\(.value.default)"' "${metadata}"
}

build() {
    local fixture="$1" feature_env="$2" tag="$3"
    docker build \
        --file "${repo_root}/test/ansible-dependency/Dockerfile" \
        --build-arg "BASE_IMAGE=${base_image}" \
        --build-arg "FIXTURE=${fixture}" \
        --build-arg "FEATURE=${feature}" \
        --build-arg "FEATURE_ENV=${feature_env}" \
        --tag "${tag}" \
        "${repo_root}" >&2
}

inspect() {
    docker run --rm --entrypoint sh "$1" -c "$2"
}

# The dependency edges of every service except the fixture itself.
edges() {
    inspect "$1" "cd ${s6_rc_dir} && find . -path '*/dependencies.d/*' -type f | grep -v '^./ansible-setup/' | sort"
}

start() {
    local image="$1" privileged="$2" mode="$3" container
    local args=(--detach)
    [ "${privileged}" = yes ] && args+=(--privileged)
    container="ansible-dependency-${feature}-${RANDOM}-$$"
    containers+=("${container}")
    docker run "${args[@]}" --name "${container}" --env "ANSIBLE_FIXTURE_MODE=${mode}" "${image}" >/dev/null
    printf '%s\n' "${container}"
}

# Prints the time in nanoseconds at which s6-rc logged "service $2$3", or
# nothing when it has not.
logged_at() {
    local container="$1" service="$2" suffix="$3" line
    line="$(docker logs --timestamps "${container}" 2>&1 \
        | grep -m 1 -F -- "s6-rc: info: service ${service}${suffix}" || true)"
    [ -n "${line}" ] || return 0
    date -u -d "${line%% *}" +%s%N
}

# Succeeds once s6-rc has logged that every service finished starting.
all_started() {
    local container="$1" service
    shift
    for service in "$@"; do
        [ -n "$(logged_at "${container}" "${service}" ' successfully started')" ] || return 1
    done
}

wait_until() {
    local attempts="$1"
    shift
    local _
    for _ in $(seq 1 "${attempts}"); do
        if "$@"; then
            return 0
        fi
        sleep 0.5
    done
    return 1
}

if ! jq -e '.installsAfter | index("ghcr.io/wyrd-company/devcontainers/ansible")' "${metadata}" >/dev/null; then
    fail "${feature} does not list the Ansible Feature in installsAfter."
fi

while IFS='|' read -r name overrides privileged services_text; do
    read -r -a services <<<"${services_text}"
    label="${feature}/${name}"
    feature_env="$(default_options | tr '\n' ' ')${overrides}"
    present_image="devcontainers-ansible-dependency-${feature}-${name}:present"
    absent_image="devcontainers-ansible-dependency-${feature}-${name}:absent"

    printf '[%s] Installing with and without ansible-setup.\n' "${label}"
    build present "${feature_env}" "${present_image}"
    build absent "${feature_env}" "${absent_image}"

    for image in "${present_image}" "${absent_image}"; do
        inspect "${image}" "/command/s6-rc-compile /tmp/compiled ${s6_rc_sources}" >/dev/null \
            || fail "[${label}] The service definitions in ${image} do not compile."
    done

    present_edges="$(edges "${present_image}")"
    absent_edges="$(edges "${absent_image}")"
    for service in "${services[@]}"; do
        grep -qx "./${service}/dependencies.d/ansible-setup" <<<"${present_edges}" \
            || fail "[${label}] ${service} does not depend on ansible-setup."
    done
    ansible_edges="$(grep -c '/dependencies.d/ansible-setup$' <<<"${present_edges}" || true)"
    [ "${ansible_edges}" -eq "${#services[@]}" ] \
        || fail "[${label}] Expected ${#services[@]} ansible-setup dependencies, found ${ansible_edges}."
    [ "$(grep -v '/dependencies.d/ansible-setup$' <<<"${present_edges}")" = "${absent_edges}" ] \
        || fail "[${label}] The installs differ beyond the ansible-setup dependency."
    ! grep -q 'ansible-setup' <<<"${absent_edges}" \
        || fail "[${label}] A dependency on ansible-setup exists without the Ansible Feature."
    inspect "${absent_image}" "test ! -e ${s6_rc_dir}/ansible-setup" \
        || fail "[${label}] The install without the fixture contains ansible-setup."

    printf '[%s] Starting services without ansible-setup.\n' "${label}"
    container="$(start "${absent_image}" "${privileged}" pass)"
    wait_until 120 all_started "${container}" "${services[@]}" \
        || { docker logs "${container}" >&2; fail "[${label}] Services did not start without ansible-setup."; }
    docker rm --force "${container}" >/dev/null

    printf '[%s] Starting services after a successful ansible-setup.\n' "${label}"
    container="$(start "${present_image}" "${privileged}" pass)"
    wait_until 240 all_started "${container}" "${services[@]}" \
        || { docker logs "${container}" >&2; fail "[${label}] Services did not start after ansible-setup finished."; }
    setup_began="$(logged_at "${container}" ansible-setup ': starting')"
    setup_finished="$(docker exec "${container}" cat /run/ansible-fixture/finished)"
    [ -n "${setup_began}" ] || fail "[${label}] s6-rc never logged ansible-setup starting."
    [ "$(( (setup_finished - setup_began) / 1000000 ))" -ge 5000 ] \
        || fail "[${label}] ansible-setup did not run long enough to prove the wait."
    for service in "${services[@]}"; do
        service_began="$(logged_at "${container}" "${service}" ': starting')"
        [ -n "${service_began}" ] || fail "[${label}] s6-rc never logged ${service} starting."
        [ "${service_began}" -ge "${setup_finished}" ] \
            || { docker logs "${container}" >&2; fail "[${label}] ${service} started before ansible-setup finished."; }
    done
    docker rm --force "${container}" >/dev/null

    printf '[%s] Starting services after a failed ansible-setup.\n' "${label}"
    container="$(start "${present_image}" "${privileged}" fail)"
    wait_until 240 docker exec "${container}" test -e /run/ansible-fixture/failed \
        || { docker logs "${container}" >&2; fail "[${label}] ansible-setup never failed."; }
    sleep 10
    [ -n "$(logged_at "${container}" ansible-setup ': starting')" ] \
        || fail "[${label}] s6-rc never logged ansible-setup starting."
    for service in "${services[@]}"; do
        [ -z "$(logged_at "${container}" "${service}" ': starting')" ] \
            || { docker logs "${container}" >&2; fail "[${label}] ${service} started although ansible-setup failed."; }
    done
    docker rm --force "${container}" >/dev/null
done < <(configurations)

printf '%s Ansible dependency checks passed.\n' "${feature}"
