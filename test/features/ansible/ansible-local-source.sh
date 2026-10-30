#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "local source is recorded" grep -qx 'SETUP_SOURCE=/srv/sample-playbooks' /etc/ansible-setup/settings
check "no checkout directory is created for a local source" test ! -e /var/lib/ansible-setup/checkout

reportResults
