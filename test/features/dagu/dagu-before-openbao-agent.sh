#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "OpenBao Agent installed after Dagu" test -x /usr/local/bin/openbao-wait-for-secrets
check "Agent reconciled Dagu to start after the secret file directory exists" test -f /etc/s6-overlay/s6-rc.d/dagu/dependencies.d/openbao-secrets
# shellcheck disable=SC2016
check "Agent reconciled the Dagu user into the secrets group" bash -c 'id -nG vscode | tr " " "\n" | grep -qx openbao-secrets'

reportResults
