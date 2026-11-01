#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

# shellcheck disable=SC2016
check "pinned Dagu version is installed" bash -c 'test "$(dagu version)" = 2.16.1'
check "localhost is normalized to IPv4 loopback" grep -q -- 'start-all --host 127.0.0.1 --port 8123' /usr/local/bin/dagu-service
check "custom service user is configured" grep -q '^exec s6-setuidgid root ' /etc/s6-overlay/s6-rc.d/dagu/run
check "custom service home is configured" grep -q ' HOME=/root ' /etc/s6-overlay/s6-rc.d/dagu/run

check "custom config path is shell quoted" grep -Fq -- '--config /etc/sample\ dagu/config.yaml' /usr/local/bin/dagu-service

reportResults
