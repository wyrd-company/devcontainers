#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "t3 command exists globally" test -x /usr/local/bin/t3
check "custom host configured" grep -q '^default_host=127.0.0.1$' /usr/local/bin/t3code-server
check "custom port configured" grep -q '^default_port=4123$' /usr/local/bin/t3code-server
check "custom release base URL configured" grep -q '^default_release_base=https://releases.example.test/t3$' /usr/local/bin/t3code-server
check "service runs as root" grep -q 's6-setuidgid root' /etc/s6-overlay/s6-rc.d/t3code-server/run
check "runtime lives in the root home" grep -qx 'T3CODE_SERVER_HOME=/root' /usr/local/lib/t3code-server/config.env
check "codex is omitted" bash -c "! command -v codex >/dev/null 2>&1"

reportResults
