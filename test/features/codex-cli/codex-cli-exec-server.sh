#!/usr/bin/env bash
# ---
# relationships:
#   verifies: codex-cli
# ---
set -e
# shellcheck disable=SC1091
source dev-container-features-test-lib
check "exec-server registered" test -f /etc/s6-overlay/user-bundles.d/user/contents.d/codex-exec-server
check "app-server disabled" test ! -e /etc/s6-overlay/user-bundles.d/user/contents.d/codex-cli
check "exec-server loopback port" grep -Fq 'exec-server --listen ws://127.0.0.1:4511' /usr/local/bin/codex-exec-server-service
check "auth arguments escaped" grep -Fq -- '--ws-token-file /run/secrets/sample\ token' /usr/local/bin/codex-exec-server-service
check "root exec-server owner" grep -Fq 's6-setuidgid root env HOME=/root USER=root' /etc/s6-overlay/s6-rc.d/codex-exec-server/run
check "exec-server launcher syntax" bash -n /usr/local/bin/codex-exec-server-service
reportResults
