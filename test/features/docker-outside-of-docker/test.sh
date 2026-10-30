#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "Docker CE CLI is installed by default" dpkg-query -W docker-ce-cli
check "Moby CLI is not installed by default" bash -c "! dpkg-query -W moby-cli >/dev/null 2>&1"
check "socket service is registered" test -f /etc/s6-overlay/user-bundles.d/user/contents.d/docker-outside-of-docker
check "socket service is a longrun" grep -qx longrun /etc/s6-overlay/s6-rc.d/docker-outside-of-docker/type
check "socket proxy runs in the foreground" grep -q '^exec socat ' /etc/s6-overlay/s6-rc.d/docker-outside-of-docker/run

check "No service depends on an absent Ansible Feature" test -z "$(find /etc/s6-overlay/s6-rc.d -name ansible-setup 2>/dev/null)"

reportResults
