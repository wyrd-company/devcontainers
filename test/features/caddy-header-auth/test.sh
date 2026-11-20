#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "server script is installed" test -x /usr/local/lib/caddy-header-auth/server.py
check "service launcher is installed" test -x /usr/local/bin/caddy-header-auth-service
check "config directory is root-owned" bash -c 'test "$(stat -c "%a %U:%G" /etc/caddy-header-auth/conf.d)" = "755 root:root"'
check "s6 service is registered" test -f /etc/s6-overlay/user-bundles.d/user/contents.d/caddy-header-auth
check "s6 service runs as vscode" grep -q 's6-setuidgid vscode' /etc/s6-overlay/s6-rc.d/caddy-header-auth/run
check "No service depends on an absent Ansible Feature" test -z "$(find /etc/s6-overlay/s6-rc.d -name ansible-setup 2>/dev/null)"

reportResults
