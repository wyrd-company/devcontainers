#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

# shellcheck disable=SC2016
check "pinned contrib version is installed" bash -c 'opentelemetry-collector --version 2>&1 | grep -Fq "0.160.0"'
check "contrib command exists globally" test -x /usr/local/bin/otelcol-contrib
check "stable command selects contrib" test "$(readlink /usr/local/bin/opentelemetry-collector)" = /usr/local/bin/otelcol-contrib
check "custom service user is configured" grep -q '^exec s6-setuidgid root ' /etc/s6-overlay/s6-rc.d/opentelemetry-collector/run
check "custom service home is configured" grep -q ' HOME=/root ' /etc/s6-overlay/s6-rc.d/opentelemetry-collector/run

reportResults
