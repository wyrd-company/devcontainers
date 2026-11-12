#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "pinned version is installed" bash -c '/usr/local/bin/vector --version | grep -q "^vector 0.60.0 "'
check "custom service user is configured" grep -q '^exec s6-setuidgid root ' /etc/s6-overlay/s6-rc.d/vector/run
check "custom service home is configured" grep -q ' HOME=/root ' /etc/s6-overlay/s6-rc.d/vector/run
check "root owns the pipeline directory" test "$(stat -c %U:%a /etc/vector/conf.d)" = root:755
check "empty apiAddress disables the API" grep -qx '  enabled: false' /etc/vector/vector.yaml
check "poll watcher is selected" grep -q -- '--watch-config-method poll' /usr/local/bin/vector-service
check "poll interval is passed" grep -q -- '--watch-config-poll-interval-seconds 5' /usr/local/bin/vector-service

reportResults
