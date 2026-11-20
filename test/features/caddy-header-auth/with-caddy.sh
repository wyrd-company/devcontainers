#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "caddy group is selected automatically" grep -q 'install -d -m 2750 -o vscode -g caddy /run/caddy-header-auth' /etc/s6-overlay/s6-rc.d/caddy-header-auth/run
check "caddy user is not in vscode group" bash -c '! id -nG caddy | tr " " "\n" | grep -qx vscode'
check "service launcher passes explicit CLI flags" grep -q -- '--socket /run/caddy-header-auth/auth.sock' /usr/local/bin/caddy-header-auth-service

reportResults
