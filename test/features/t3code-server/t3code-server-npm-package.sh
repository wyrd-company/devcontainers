#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

T3_HOME="$(getent passwd vscode | cut -d: -f6)"
VERSION_DIR="${T3_HOME}/.t3/runtime/versions/0.0.45"

check "npm T3 reports the package version" test "$(/usr/local/bin/t3 --version)" = "t3 v0.0.45"
check "npm package is installed inside its pinned runtime" test -f "${VERSION_DIR}/npm/lib/node_modules/t3/package.json"
check "npm runtime install is marked complete" test "$(cat "${VERSION_DIR}/.install-complete")" = 0.0.45
check "npm runtime execs the platform binary rather than the t3 shim" \
    grep -q "/npm/lib/node_modules/t3/node_modules/@t3code/t3-linux-" "${VERSION_DIR}/t3"

reportResults
