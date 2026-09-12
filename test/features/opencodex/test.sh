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
check "system ocx wrapper exists" test -x /usr/local/bin/ocx
check "system opencodex alias targets the wrapper" test "$(readlink -f /usr/local/bin/opencodex)" = /usr/local/bin/ocx
check "wrapper targets the user installation" grep -q "^ocx=${OCX}$" /usr/local/bin/ocx
check "wrapper holds the service during update" grep -q '^holds=/run/opencodex/holds$' /usr/local/bin/ocx
check "wrapper serializes updates" grep -q '^lock=/run/opencodex/update.lock$' /usr/local/bin/ocx
check "wrapper reports version" bash -c "/usr/local/bin/ocx --version | grep -q '^opencodex '"
check "service launcher uses the default port" grep -q '^port=10100$' /usr/local/bin/opencodex-service
check "service launcher marks the service" grep -q '^export OCX_SERVICE=1$' /usr/local/bin/opencodex-service
check "service launcher honors the pause file" grep -q '^gate=/run/opencodex/paused$' /usr/local/bin/opencodex-service
check "service launcher honors update holds" grep -q '^holds=/run/opencodex/holds$' /usr/local/bin/opencodex-service
check "s6 service is registered" test -f /etc/s6-overlay/user-bundles.d/user/contents.d/opencodex
check "s6 service is a longrun" grep -qx longrun /etc/s6-overlay/s6-rc.d/opencodex/type
check "s6 service runs as the service user" grep -q "s6-setuidgid ${SERVICE_USER} " /etc/s6-overlay/s6-rc.d/opencodex/run
check "Caddy fragment is absent without dnsName" test ! -e /etc/caddy/conf.d/opencodex.caddy

reportResults
