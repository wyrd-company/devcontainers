#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

SERVICE_HOME="$(getent passwd vscode | cut -d: -f6)"

check "pinned OpenCodex version is installed" test "$(env HOME="${SERVICE_HOME}" "${SERVICE_HOME}/.local/bin/ocx" --version)" = "opencodex 2.50.0"
check "package manifest matches the pinned version" grep -q '"version": "2.50.0"' "${SERVICE_HOME}/.local/lib/node_modules/@bitkyc08/opencodex/package.json"

reportResults
