#!/bin/sh
# Registers a stand-in for the Ansible Feature's `ansible-setup` s6-rc oneshot.
#
# The oneshot waits, then writes the time in nanoseconds to
# /run/ansible-fixture/finished. With
# ANSIBLE_FIXTURE_MODE=fail it writes /run/ansible-fixture/failed and exits
# non-zero instead.

set -eu

service_dir=/etc/s6-overlay/s6-rc.d/ansible-setup
mkdir -p "${service_dir}/dependencies.d"
printf 'oneshot\n' >"${service_dir}/type"
touch "${service_dir}/dependencies.d/base"
printf '/usr/local/bin/ansible-setup-fixture\n' >"${service_dir}/up"
touch /etc/s6-overlay/user-bundles.d/user/contents.d/ansible-setup

cat >/usr/local/bin/ansible-setup-fixture <<'SCRIPT'
#!/command/with-contenv sh
mkdir -p /run/ansible-fixture
sleep 6
if [ "${ANSIBLE_FIXTURE_MODE:-}" = fail ]; then
    : >/run/ansible-fixture/failed
    exit 1
fi
date +%s%N >/run/ansible-fixture/finished
SCRIPT
chmod 0755 /usr/local/bin/ansible-setup-fixture
