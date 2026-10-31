#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

OPENOBSERVE_HOME_DIR="$(getent passwd vscode | cut -d: -f6)"

check "OpenObserve command exists globally" test -x /usr/local/bin/openobserve
check "OpenObserve version works as service user" env HOME="${OPENOBSERVE_HOME_DIR}" /usr/local/bin/openobserve --version
check "OpenObserve launcher is executable" test -x /usr/local/bin/openobserve-service
check "OpenObserve service is registered" test -f /etc/s6-overlay/user-bundles.d/user/contents.d/openobserve
check "OpenObserve service is a longrun" grep -qx longrun /etc/s6-overlay/s6-rc.d/openobserve/type
check "OpenObserve service runs as the automatic service user" grep -q '^exec s6-setuidgid vscode ' /etc/s6-overlay/s6-rc.d/openobserve/run
check "OpenObserve service receives the service user home" grep -q ' HOME=/home/vscode ' /etc/s6-overlay/s6-rc.d/openobserve/run
check "OpenObserve service receives the service user name" grep -q ' USER=vscode ' /etc/s6-overlay/s6-rc.d/openobserve/run
check "OpenObserve binds to IPv4 loopback by default" grep -q 'export ZO_HTTP_ADDR=127.0.0.1' /usr/local/bin/openobserve-service
check "OpenObserve default HTTP port is 5080" grep -q 'export ZO_HTTP_PORT=5080' /usr/local/bin/openobserve-service
check "OpenObserve default gRPC port is 5081" grep -q 'export ZO_GRPC_PORT=5081' /usr/local/bin/openobserve-service
check "OpenObserve default root user email is set" grep -Fq 'export ZO_ROOT_USER_EMAIL=root@example.com' /usr/local/bin/openobserve-service
check "OpenObserve default root user password is set" grep -Fq 'export ZO_ROOT_USER_PASSWORD=Complexpass#123' /usr/local/bin/openobserve-service
check "OpenObserve telemetry is disabled by default" grep -Fq 'export ZO_TELEMETRY=false' /usr/local/bin/openobserve-service
check "OpenObserve Feature does not export an S3 bucket prefix by default" bash -c '! grep -q ZO_S3_BUCKET_PREFIX /usr/local/bin/openobserve-service'
check "OpenObserve Feature does not create a managed config" test ! -e /etc/openobserve/openobserve.env
check "OpenObserve Feature does not register systemd" test ! -e /etc/systemd/system/openobserve.service

check "No service depends on an absent Ansible Feature" test -z "$(find /etc/s6-overlay/s6-rc.d -name ansible-setup 2>/dev/null)"

reportResults
