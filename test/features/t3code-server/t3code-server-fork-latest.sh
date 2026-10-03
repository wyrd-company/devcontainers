#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

T3_HOME="$(getent passwd vscode | cut -d: -f6)"
installed_version="$(/usr/local/bin/t3 --version)"
selected="$(/usr/local/lib/t3code-server/t3code-runtime selected-version)"

check "fork T3 command exists globally" test -x /usr/local/bin/t3
check "latest resolves to a fork build" bash -c "printf '%s\n' '${installed_version}' | grep -Eq '^t3 v[0-9]+\.[0-9]+\.[0-9]+-wyrd\.[0-9]+$'"
check "selected version is the installed fork build" test "${installed_version}" = "t3 v${selected}"
check "fork runtime is pinned under the service home" test -x "${T3_HOME}/.t3/runtime/versions/${selected}/t3"
check "service wrapper defaults to the web runtime" grep -qx 'default_mode=web' /usr/local/bin/t3code-server
check "s6 service is registered" test -f /etc/s6-overlay/user-bundles.d/user/contents.d/t3code-server

reportResults
