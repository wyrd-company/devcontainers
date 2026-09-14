#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

FEATURE_USER=root
if id -u vscode >/dev/null 2>&1; then
    FEATURE_USER=vscode
fi
USER_HOME="$(getent passwd "${FEATURE_USER}" | cut -d: -f6)"
PI="${USER_HOME}/.local/bin/pi"

check "pi command exists" test -x "${PI}"
check "pi version works as user" env HOME="${USER_HOME}" "${PI}" --version
check "pi executable is user-owned" test "$(stat -c %U "$(readlink -f "${PI}")")" = "${FEATURE_USER}"
check "pi package is user-owned" test "$(stat -c %U "${USER_HOME}/.local/lib/node_modules/@earendil-works/pi-coding-agent")" = "${FEATURE_USER}"
# shellcheck disable=SC2016
check "node major is 24" bash -c 'test "$(node -p "process.versions.node.split(\".\")[0]")" = 24'
check "system pi link targets user installation" test "$(readlink -f /usr/local/bin/pi)" = "$(readlink -f "${PI}")"

reportResults
