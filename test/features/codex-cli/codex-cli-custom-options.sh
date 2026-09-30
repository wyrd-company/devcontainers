#!/usr/bin/env bash
set -e
# shellcheck disable=SC1091
source dev-container-features-test-lib
check "root owns Codex" test "$(stat -c %U /root/.local/lib/node_modules/@openai/codex)" = root
check "remote control enabled on canonical listener" grep -Fq 'app-server --listen unix:// --remote-control' /usr/local/bin/codex-cli-service
check "service runs as root" grep -Fq 's6-setuidgid root env HOME=/root USER=root' /etc/s6-overlay/s6-rc.d/codex-cli/run
reportResults
