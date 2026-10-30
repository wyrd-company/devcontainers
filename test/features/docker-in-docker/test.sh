#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "Docker CE engine is installed by default" dpkg-query -W docker-ce
check "Moby engine is not installed by default" bash -c "! dpkg-query -W moby-engine >/dev/null 2>&1"
check "containerd service is registered" grep -qx longrun /etc/s6-overlay/s6-rc.d/docker-in-docker-containerd/type
check "Docker daemon service is registered" test -f /etc/s6-overlay/user-bundles.d/user/contents.d/docker-in-docker
check "dockerd runs in the foreground" grep -q '^exec dockerd ' /etc/s6-overlay/s6-rc.d/docker-in-docker/run

check "No service depends on an absent Ansible Feature" test -z "$(find /etc/s6-overlay/s6-rc.d -name ansible-setup 2>/dev/null)"

reportResults
