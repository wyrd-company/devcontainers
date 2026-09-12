#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

FRAGMENT=/etc/caddy/conf.d/opencodex.caddy

check "Caddy is installed before OpenCodex writes its fragment" test -x /usr/bin/caddy
check "OpenCodex Caddy fragment exists" test -f "${FRAGMENT}"
check "OpenCodex DNS name is configured" grep -q '^ocx\.test-container\.example\.test {$' "${FRAGMENT}"
check "OpenCodex port is proxied on loopback" grep -q '^    reverse_proxy 127\.0\.0\.1:4123 {$' "${FRAGMENT}"
check "upstream receives a loopback Host" grep -q '^        header_up Host {upstream_hostport}$' "${FRAGMENT}"
check "dashboard Origin is matched exactly" grep -q '^    @dashboard_origin header Origin https://ocx\.test-container\.example\.test$' "${FRAGMENT}"
check "dashboard Origin is rewritten to loopback" grep -q '^    request_header @dashboard_origin Origin http://127\.0\.0\.1:4123$' "${FRAGMENT}"
check "OpenCodex DNS name is registered for startup readiness" grep -qx 'ocx\.test-container\.example\.test' /etc/caddy/required-hosts.d/opencodex.host
check "combined Caddy configuration is valid" caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

reportResults
