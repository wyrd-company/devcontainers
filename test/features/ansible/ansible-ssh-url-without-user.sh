#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "an ssh URL with a port and no user is recorded" grep -qx 'SETUP_SOURCE=ssh://example.test:2222/sample-playbooks.git' /etc/ansible-setup/settings

reportResults
