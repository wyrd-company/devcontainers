#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

# shellcheck disable=SC2016
check "pinned OpenBao version is installed" bash -c 'bao version | grep -Fq "OpenBao v2.6.1"'
check "automatic service user overrides the root default" grep -q '^exec s6-setuidgid vscode ' /etc/s6-overlay/s6-rc.d/openbao-agent/run
check "custom service home is configured" grep -q ' HOME=/home/vscode ' /etc/s6-overlay/s6-rc.d/openbao-agent/run
check "custom configuration directory exists" test -d /etc/custom-openbao
check "custom configuration path is configured" grep -Fq 'config_path=/etc/custom-openbao/agent.hcl' /usr/local/bin/openbao-agent-service

reportResults
