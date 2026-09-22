#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

AGENT_HOME_DIR="$(getent passwd vscode | cut -d: -f6)"

check "OpenBao command exists globally" test -x /usr/local/bin/bao
check "OpenBao version works as service user" env HOME="${AGENT_HOME_DIR}" /usr/local/bin/bao version
check "Vault compatibility alias is not installed" test ! -e /usr/local/bin/vault
check "Agent launcher is executable" test -x /usr/local/bin/openbao-agent-service
check "default configuration directory exists" test -d /etc/openbao
check "Feature does not invent an Agent configuration" test ! -e /etc/openbao/agent.hcl
# shellcheck disable=SC2016
check "Agent launcher fails closed without configuration" bash -c \
    'output="$(/usr/local/bin/openbao-agent-service 2>&1)"; status=$?; test "$status" -ne 0 && printf "%s\n" "$output" | grep -Fq "Configuration is not readable at /etc/openbao/agent.hcl"'
check "Agent service is registered" test -f /etc/s6-overlay/user-bundles.d/user/contents.d/openbao-agent
check "Agent service is a longrun" grep -qx longrun /etc/s6-overlay/s6-rc.d/openbao-agent/type
check "Agent service runs as root by default" grep -q '^exec s6-setuidgid root ' /etc/s6-overlay/s6-rc.d/openbao-agent/run
check "Agent service receives the service user home" grep -q ' HOME=/root ' /etc/s6-overlay/s6-rc.d/openbao-agent/run
check "Agent service receives the service user name" grep -q ' USER=root ' /etc/s6-overlay/s6-rc.d/openbao-agent/run
check "secret file group exists" getent group openbao-secrets
check "secret file wait helper is executable" test -x /usr/local/bin/openbao-wait-for-secrets
check "wait helper rejects a missing Feature id" bash -c '/usr/local/bin/openbao-wait-for-secrets; test "$?" -eq 2'
check "wait helper does not wait without a configuration" timeout 5 /usr/local/bin/openbao-wait-for-secrets sample-feature
check "secret file directory service is a oneshot" grep -qx oneshot /etc/s6-overlay/s6-rc.d/openbao-secrets/type
check "secret file directory service is registered" test -f /etc/s6-overlay/user-bundles.d/user/contents.d/openbao-secrets
check "Agent starts after the secret file directory exists" test -f /etc/s6-overlay/s6-rc.d/openbao-agent/dependencies.d/openbao-secrets
# shellcheck disable=SC2016
check "secret file directory belongs to the Agent user" grep -Fq -- '-m 2750 -o root -g openbao-secrets "${secrets_dir}"' /usr/local/bin/openbao-prepare-secrets
check "secret file directory refuses a mount point" grep -Fq -- 'findmnt --raw --noheadings --output TARGET' /usr/local/bin/openbao-prepare-secrets
check "Agent Feature does not register systemd" test ! -e /etc/systemd/system/openbao-agent.service

reportResults
