#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "OpenBao Agent is installed before Collector" test -x /usr/local/bin/openbao-wait-for-secrets
check "Collector starts after the secret file directory exists" test -f /etc/s6-overlay/s6-rc.d/opentelemetry-collector/dependencies.d/openbao-secrets
# shellcheck disable=SC2016
check "Collector user can read rendered secret files" bash -c 'id -nG vscode | tr " " "\n" | grep -qx openbao-secrets'

reportResults
