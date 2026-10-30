#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "sshd service is registered" test -f /etc/s6-overlay/user-bundles.d/user/contents.d/sshd
check "sshd is a longrun service" grep -qx longrun /etc/s6-overlay/s6-rc.d/sshd/type
check "sshd runs in the foreground" grep -q 'sshd -D -e' /etc/s6-overlay/s6-rc.d/sshd/run
check "public key authentication is required" grep -qx 'AuthenticationMethods publickey' /etc/ssh/sshd_config.d/00-devcontainer-key-only.conf
check "root login is disabled" grep -qx 'PermitRootLogin no' /etc/ssh/sshd_config.d/00-devcontainer-key-only.conf
check "password authentication is disabled" grep -qx 'PasswordAuthentication no' /etc/ssh/sshd_config.d/00-devcontainer-key-only.conf
check "keyboard-interactive authentication is disabled" grep -qx 'KbdInteractiveAuthentication no' /etc/ssh/sshd_config.d/00-devcontainer-key-only.conf
check "host keys are read from the persistent volume" grep -qx 'HostKey /etc/ssh/keys/ssh_host_ed25519_key' /etc/ssh/sshd_config.d/10-persistent-host-keys.conf
# shellcheck disable=SC2016
check "run script seeds persistent host keys" grep -q 'key="/etc/ssh/keys/ssh_host_${keytype}_key"' /etc/s6-overlay/s6-rc.d/sshd/run

check "No service depends on an absent Ansible Feature" test -z "$(find /etc/s6-overlay/s6-rc.d -name ansible-setup 2>/dev/null)"

reportResults
