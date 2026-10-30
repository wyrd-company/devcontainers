#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "Ansible playbook command exists" ansible-playbook --version
check "Ansible Galaxy command exists" ansible-galaxy --version
check "Git exists for playbook sources" git --version
check "ansible-sync is executable" test -x /usr/local/bin/ansible-sync
check "ansible-setup launcher is executable" test -x /usr/local/bin/ansible-setup
check "ansible-setup runs with the container environment" grep -qx '#!/command/with-contenv bash' /usr/local/bin/ansible-setup
check "ansible-setup is registered" test -f /etc/s6-overlay/user-bundles.d/user/contents.d/ansible-setup
check "ansible-setup is a oneshot" grep -qx oneshot /etc/s6-overlay/s6-rc.d/ansible-setup/type
check "ansible-setup depends on the base bundle" test -f /etc/s6-overlay/s6-rc.d/ansible-setup/dependencies.d/base
check "ansible-setup depends on nothing else" test "$(find /etc/s6-overlay/s6-rc.d/ansible-setup/dependencies.d -type f | wc -l)" -eq 1
check "ansible-setup runs the launcher" grep -qx /usr/local/bin/ansible-setup /etc/s6-overlay/s6-rc.d/ansible-setup/up
check "ansible-setup does not depend on OpenBao Agent" test ! -e /etc/s6-overlay/s6-rc.d/ansible-setup/dependencies.d/openbao-secrets
check "default service user is root" grep -qx 'SETUP_USER=root' /etc/ansible-setup/settings
check "default playbook is site.yml" grep -qx 'SETUP_PLAYBOOK=site.yml' /etc/ansible-setup/settings
check "default checkout directory" grep -qx 'SETUP_CHECKOUT=/var/lib/ansible-setup/checkout' /etc/ansible-setup/settings
check "settings hold no source by default" grep -qx "SETUP_SOURCE=''" /etc/ansible-setup/settings
check "state directory is owned by root" test "$(stat -c %U /var/lib/ansible-setup)" = root
check "lock directory is owned by the service user" test "$(stat -c %U /var/lib/ansible-setup/lock.d)" = root
check "startup without a source succeeds" /usr/local/bin/ansible-sync --startup
check_fails() { ! "$@"; }
check "ansible-sync without a source fails" check_fails /usr/local/bin/ansible-sync
check "Feature does not register systemd" test ! -e /etc/systemd/system/ansible-setup.service

reportResults
