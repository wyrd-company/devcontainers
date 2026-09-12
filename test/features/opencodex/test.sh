#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

SERVICE_USER=root
if id -u vscode >/dev/null 2>&1; then
    SERVICE_USER=vscode
fi
SERVICE_HOME="$(getent passwd "${SERVICE_USER}" | cut -d: -f6)"
OCX="${SERVICE_HOME}/.local/bin/ocx"
PACKAGE_DIR="${SERVICE_HOME}/.local/lib/node_modules/@bitkyc08/opencodex"

check "ocx launcher exists in the service user's prefix" test -x "${OCX}"
check "ocx version works as service user" bash -c "env HOME=${SERVICE_HOME} ${OCX} --version | grep -q '^opencodex '"
check "package is user-owned" test "$(stat -c %U "${PACKAGE_DIR}")" = "${SERVICE_USER}"
check "package scope is user-owned" test "$(stat -c %U "$(dirname "${PACKAGE_DIR}")")" = "${SERVICE_USER}"
check "bin prefix is user-owned" test "$(stat -c %U "${SERVICE_HOME}/.local/bin")" = "${SERVICE_USER}"
check "state directory is user-owned" test "$(stat -c %U "${SERVICE_HOME}/.opencodex")" = "${SERVICE_USER}"
check "Codex home is user-owned" test "$(stat -c %U "${SERVICE_HOME}/.codex")" = "${SERVICE_USER}"
check "system ocx wrapper exists" test -x /usr/local/bin/ocx
check "system opencodex alias targets the wrapper" test "$(readlink -f /usr/local/bin/opencodex)" = /usr/local/bin/ocx
check "wrapper targets the user installation" grep -q "^ocx=${OCX}$" /usr/local/bin/ocx
check "wrapper reports version" bash -c "/usr/local/bin/ocx --version | grep -q '^opencodex '"
check "standalone launcher is absent in client mode" test ! -e /usr/local/bin/opencodex-service
check "standalone service is absent in client mode" test ! -e /etc/s6-overlay/s6-rc.d/opencodex
check "client sync service is registered" test -f /etc/s6-overlay/user-bundles.d/user/contents.d/opencodex-client-sync
check "client sync service is a oneshot" grep -qx oneshot /etc/s6-overlay/s6-rc.d/opencodex-client-sync/type
check "client sync runs as the service user" grep -q "s6-setuidgid ${SERVICE_USER} " /etc/s6-overlay/s6-rc.d/opencodex-client-sync/up
check "client sync checks persisted connection state" grep -q 'connect status --json' /usr/local/bin/opencodex-client-sync
# shellcheck disable=SC2016
check "client sync refreshes connected clients" grep -q '"\${ocx}" sync' /usr/local/bin/opencodex-client-sync
check "Caddy fragment is absent without dnsName" test ! -e /etc/caddy/conf.d/opencodex.caddy

SYNC_TEST_DIR="$(mktemp -d)"
trap 'rm -rf "${SYNC_TEST_DIR}"' EXIT
cp /usr/local/bin/opencodex-client-sync "${SYNC_TEST_DIR}/client-sync"
cat >"${SYNC_TEST_DIR}/ocx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1-}" = connect ] && [ "${2-}" = status ] && [ "${3-}" = --json ]; then
    [ "${FAKE_STATUS-}" != command-failure ] || exit 1
    printf '%s\n' "${FAKE_STATUS-}"
    exit 0
fi

if [ "${1-}" = sync ]; then
    : >"${FAKE_SYNC_LOG:?}"
    exit "${FAKE_SYNC_EXIT-0}"
fi

exit 64
EOF
chmod 0755 "${SYNC_TEST_DIR}/ocx" "${SYNC_TEST_DIR}/client-sync"
sed -i "s|^ocx=.*$|ocx=${SYNC_TEST_DIR}/ocx|" "${SYNC_TEST_DIR}/client-sync"

run_sync_case() {
    rm -f "${SYNC_TEST_DIR}/sync.log"
    FAKE_STATUS="$1" FAKE_SYNC_LOG="${SYNC_TEST_DIR}/sync.log" "${SYNC_TEST_DIR}/client-sync" >/dev/null 2>&1
}

connected_sync_case() {
    run_sync_case '{"state":"connected","token":"owned"}' && test -f "${SYNC_TEST_DIR}/sync.log"
}

no_sync_case() {
    run_sync_case "$1" && test ! -e "${SYNC_TEST_DIR}/sync.log"
}

failed_sync_case() {
    rm -f "${SYNC_TEST_DIR}/sync.log"
    FAKE_STATUS='{"state":"connected","token":"owned"}' FAKE_SYNC_EXIT=1 FAKE_SYNC_LOG="${SYNC_TEST_DIR}/sync.log" \
        "${SYNC_TEST_DIR}/client-sync" >/dev/null 2>&1
}

check "connected startup performs one sync" connected_sync_case
check "disconnected startup does not sync" no_sync_case '{"state":"disconnected","token":"missing"}'
check "changed client token does not sync" no_sync_case '{"state":"connected","token":"changed"}'
check "invalid status does not sync or block startup" no_sync_case not-json
check "status failure does not sync or block startup" no_sync_case command-failure
check "sync failure does not block startup" failed_sync_case

reportResults
