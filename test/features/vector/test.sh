#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "Vector command exists globally" test -x /usr/local/bin/vector
check "Vector version works" /usr/local/bin/vector --version
check "managed configuration is owned by root" test "$(stat -c %U:%a /etc/vector/vector.yaml)" = root:644
# The Dev Container CLI may have changed the service user's UID since install,
# and s6 does not run here to hand the directories over, so compare with the
# IDs the installer recorded.
run_script=/etc/s6-overlay/s6-rc.d/vector/run
install_ids="$(sed -n 's/^install_uid=//p' "${run_script}"):$(sed -n 's/^install_gid=//p' "${run_script}")"
check "service records the install-time service user IDs" test "${install_ids}" != :
check "pipeline directory is owned by the install-time service user" test "$(stat -c %u:%g:%a /etc/vector/conf.d)" = "${install_ids}:755"
check "data directory is owned by the install-time service user" test "$(stat -c %u:%g:%a /var/lib/vector)" = "${install_ids}:750"
check "API listens on loopback" grep -qx '  address: "127.0.0.1:8686"' /etc/vector/vector.yaml
check "openbao secret backend is configured" grep -A4 -x '  openbao:' /etc/vector/vector.yaml
check "openbao secret backend runs bao-secret" bash -c "grep -A5 -x '  openbao:' /etc/vector/vector.yaml | grep -qx '      - /usr/local/bin/bao-secret'"
check "no environment secret backend is configured" bash -c "! grep -q 'environment:' /etc/vector/vector.yaml"
check "no environment secret backend is installed" test ! -e /usr/local/bin/vector-secret-environment
check "Vector launcher is executable" test -x /usr/local/bin/vector-service
check "Vector launcher watches the pipeline directory" grep -qx '__vector_service_config_dir=/etc/vector/conf.d' /usr/local/bin/vector-service
check "Vector launcher uses the recommended watcher" grep -qx '__vector_service_watch_method=recommended' /usr/local/bin/vector-service
check "Vector launcher reads no secret file" bash -c "! grep -q /run/openbao /usr/local/bin/vector-service"
check "Vector service is registered" test -f /etc/s6-overlay/user-bundles.d/user/contents.d/vector
check "Vector service is a longrun" grep -qx longrun /etc/s6-overlay/s6-rc.d/vector/type
check "Vector service depends on base" test -f /etc/s6-overlay/s6-rc.d/vector/dependencies.d/base
check "Vector service runs as the automatic service user" grep -q '^exec s6-setuidgid vscode ' /etc/s6-overlay/s6-rc.d/vector/run
check "Vector service receives the service user home" grep -q ' HOME=/home/vscode ' /etc/s6-overlay/s6-rc.d/vector/run
check "Vector service receives the service user name" grep -q ' USER=vscode ' /etc/s6-overlay/s6-rc.d/vector/run
check "Vector does not depend on the OpenBao Agent Feature" test ! -e /etc/s6-overlay/s6-rc.d/vector/dependencies.d/openbao-secrets
check "Vector Feature does not register systemd" test ! -e /etc/systemd/system/vector.service

check "No service depends on an absent Ansible Feature" test -z "$(find /etc/s6-overlay/s6-rc.d -name ansible-setup 2>/dev/null)"

reportResults
