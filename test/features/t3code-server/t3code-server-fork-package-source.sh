#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

T3_HOME="$(getent passwd vscode | cut -d: -f6)"

check "fork T3 command exists globally" test -x /usr/local/bin/t3
check "fork T3 reports the published version" test "$(/usr/local/bin/t3 --version)" = "t3 v0.0.42-wyrd.2"
check "fork runtime is pinned under the service home" test -x "${T3_HOME}/.t3/runtime/versions/0.0.42-wyrd.2/t3"
check "fork runtime install is marked complete" test "$(cat "${T3_HOME}/.t3/runtime/versions/0.0.42-wyrd.2/.install-complete")" = 0.0.42-wyrd.2

reportResults
