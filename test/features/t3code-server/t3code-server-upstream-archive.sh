#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

T3_HOME="$(getent passwd vscode | cut -d: -f6)"

check "upstream T3 command exists globally" test -x /usr/local/bin/t3
check "upstream T3 reports the pinned version" test "$(/usr/local/bin/t3 --version)" = "t3 v0.0.42"
check "upstream runtime is a release archive, not an npm install" test ! -e /usr/local/lib/t3code-server/npm
check "release archive executable is unpacked in place" test -x "${T3_HOME}/.t3/runtime/versions/0.0.42/t3"
check "release archive carries its web client" test -f "${T3_HOME}/.t3/runtime/versions/0.0.42/client/index.html"
check "release archive install is marked complete" test "$(cat "${T3_HOME}/.t3/runtime/versions/0.0.42/.install-complete")" = 0.0.42

reportResults
