#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "caddy is installed" caddy version
check "caddy service is registered" test -f /etc/s6-overlay/user-bundles.d/user/contents.d/caddy
check "watcher service is registered" test -f /etc/s6-overlay/user-bundles.d/user/contents.d/caddy-config-watcher
check "admin uses a Unix socket" grep -Eq '^[[:space:]]+admin unix//run/caddy/admin\.sock$' /etc/caddy/Caddyfile
check "fragment wildcard is imported" grep -q '^import /etc/caddy/conf.d/\*.caddy$' /etc/caddy/Caddyfile
check "fragment directory is setgid" test "$(stat -c %a /etc/caddy/conf.d)" = 2775
check "required-host directory is setgid" test "$(stat -c %a /etc/caddy/required-hosts.d)" = 2775
check "Caddy waits for registered DNS names" grep -q '^/usr/local/bin/caddy-wait-for-dns$' /etc/s6-overlay/s6-rc.d/caddy/run
check "reloads wait for registered DNS names" grep -q '^/usr/local/bin/caddy-wait-for-dns$' /usr/local/bin/caddy-reload
# shellcheck disable=SC2016
check "DNS readiness blocks until a registered name resolves" bash -c '
    hostname=unresolved-host.invalid
    printf "%s\n" "${hostname}" >/etc/caddy/required-hosts.d/readiness-test.host
    if timeout 1 /usr/local/bin/caddy-wait-for-dns >/dev/null 2>&1; then
        exit 1
    fi
    printf "%s\n" localhost >/etc/caddy/required-hosts.d/readiness-test.host
    /usr/local/bin/caddy-wait-for-dns
    rm /etc/caddy/required-hosts.d/readiness-test.host
'
check "remote user can manage fragments" bash -c 'id -nG vscode | tr " " "\n" | grep -qx caddy-config'
check "admin socket is not exposed to config authors" bash -c '! id -nG vscode | tr " " "\n" | grep -qx caddy'

check "No service depends on an absent Ansible Feature" test -z "$(find /etc/s6-overlay/s6-rc.d -name ansible-setup 2>/dev/null)"

reportResults
