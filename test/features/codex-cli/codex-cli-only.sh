#!/usr/bin/env bash
set -e
# shellcheck disable=SC1091
source dev-container-features-test-lib
# shellcheck disable=SC2016
check "pinned CLI works" bash -c 'test "$(codex --version)" = "codex-cli 0.154.0"'
check "no service launcher" test ! -e /usr/local/bin/codex-cli-service
check "no s6 registration" test ! -e /etc/s6-overlay/s6-rc.d/codex-cli
reportResults
