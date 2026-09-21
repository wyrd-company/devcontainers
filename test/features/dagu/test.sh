#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

DAGU_HOME_DIR="$(getent passwd vscode | cut -d: -f6)"

check "Dagu command exists globally" test -x /usr/local/bin/dagu
check "Dagu version works as service user" env HOME="${DAGU_HOME_DIR}" /usr/local/bin/dagu version
check "Dagu launcher is executable" test -x /usr/local/bin/dagu-service
check "Dagu service is registered" test -f /etc/s6-overlay/user-bundles.d/user/contents.d/dagu
check "Dagu service is a longrun" grep -qx longrun /etc/s6-overlay/s6-rc.d/dagu/type
check "Dagu service runs as the automatic service user" grep -q '^exec s6-setuidgid vscode ' /etc/s6-overlay/s6-rc.d/dagu/run
check "Dagu service receives the service user home" grep -q ' HOME=/home/vscode ' /etc/s6-overlay/s6-rc.d/dagu/run
check "Dagu service receives the service user name" grep -q ' USER=vscode ' /etc/s6-overlay/s6-rc.d/dagu/run
check "Dagu binds to IPv4 loopback by default" grep -q -- 'start-all --host 127.0.0.1 --port 8080' /usr/local/bin/dagu-service
check "Dagu Feature does not create a managed config" test ! -e /etc/dagu/config.yaml
check "Dagu launcher loads the conventional secret file" grep -Fq 'secret_file=/run/openbao/secrets/dagu.env' /usr/local/bin/dagu-service
check "Dagu does not depend on an absent OpenBao Agent Feature" test ! -e /etc/s6-overlay/s6-rc.d/dagu/dependencies.d/openbao-secrets
check "Dagu Feature does not register systemd" test ! -e /etc/systemd/system/dagu.service

reportResults
