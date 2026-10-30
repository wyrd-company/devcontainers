#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "source is recorded" grep -qx 'SETUP_SOURCE=ssh://git@example.test:2222/sample-team/sample-playbooks.git' /etc/ansible-setup/settings
check "playbook is recorded" grep -qx 'SETUP_PLAYBOOK=container/site.yml' /etc/ansible-setup/settings
check "ref is recorded" grep -qx 'SETUP_REF=release-1' /etc/ansible-setup/settings
check "inventory is recorded" grep -qx 'SETUP_INVENTORY=inventory/local.ini' /etc/ansible-setup/settings
check "requirements are recorded" grep -qx 'SETUP_REQUIREMENTS=requirements.yml' /etc/ansible-setup/settings
check "arguments are recorded as one value" grep -qx 'SETUP_ARGS=--tags\\ base\\ -e\\ sample_flag=true' /etc/ansible-setup/settings
check "automatic service user is the remote user" grep -qx 'SETUP_USER=vscode' /etc/ansible-setup/settings
check "settings are not writable by the service user" test ! -w /etc/ansible-setup/settings
check_fails() { ! "$@"; }
check "automatic sudo user may run ansible-sync" sudo -n -l /usr/local/bin/ansible-sync
check "the sudo rule allows no arguments" check_fails sudo -n -l /usr/local/bin/ansible-sync --startup
check "the sudo rule allows no other command" check_fails sudo -n -l /bin/true
check "the sudoers file is root only" test "$(stat -c '%U %a' /etc/sudoers.d/ansible)" = "root 440"

reportResults
