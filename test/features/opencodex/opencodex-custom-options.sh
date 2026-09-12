#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "custom port configured" grep -q '^port=4123$' /usr/local/bin/opencodex-service
check "service runs as root" grep -q 's6-setuidgid root ' /etc/s6-overlay/s6-rc.d/opencodex/run
check "standalone update wrapper holds the service" grep -q '^holds=/run/opencodex/holds$' /usr/local/bin/ocx
check "standalone update wrapper serializes updates" grep -q '^lock=/run/opencodex/update.lock$' /usr/local/bin/ocx
check "wrapper targets the root installation" grep -q '^ocx=/root/.local/bin/ocx$' /usr/local/bin/ocx

reportResults
