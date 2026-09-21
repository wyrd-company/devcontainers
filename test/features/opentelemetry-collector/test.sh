#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

COLLECTOR_HOME_DIR="$(getent passwd vscode | cut -d: -f6)"

check "stable Collector command exists globally" test -x /usr/local/bin/opentelemetry-collector
check "core command exists globally" test -x /usr/local/bin/otelcol
check "Collector version works as service user" env HOME="${COLLECTOR_HOME_DIR}" /usr/local/bin/opentelemetry-collector --version
check "starter configuration is readable" test -r /etc/opentelemetry-collector/config.yaml
check "starter configuration is valid" env HOME="${COLLECTOR_HOME_DIR}" /usr/local/bin/opentelemetry-collector validate --config=/etc/opentelemetry-collector/config.yaml
check "Collector launcher is executable" test -x /usr/local/bin/opentelemetry-collector-service
check "Collector service is registered" test -f /etc/s6-overlay/user-bundles.d/user/contents.d/opentelemetry-collector
check "Collector service is a longrun" grep -qx longrun /etc/s6-overlay/s6-rc.d/opentelemetry-collector/type
check "Collector service runs as the automatic service user" grep -q '^exec s6-setuidgid vscode ' /etc/s6-overlay/s6-rc.d/opentelemetry-collector/run
check "Collector service receives the service user home" grep -q ' HOME=/home/vscode ' /etc/s6-overlay/s6-rc.d/opentelemetry-collector/run
check "Collector service receives the service user name" grep -q ' USER=vscode ' /etc/s6-overlay/s6-rc.d/opentelemetry-collector/run
check "Collector launcher loads the conventional secret file" grep -Fq 'secret_file=/run/openbao/secrets/opentelemetry-collector.env' /usr/local/bin/opentelemetry-collector-service
check "Collector does not depend on an absent OpenBao Agent Feature" test ! -e /etc/s6-overlay/s6-rc.d/opentelemetry-collector/dependencies.d/openbao-secrets
check "Collector Feature does not register systemd" test ! -e /etc/systemd/system/otelcol.service

reportResults
