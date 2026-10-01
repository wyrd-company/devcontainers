#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

T3_HOME="$(getent passwd vscode | cut -d: -f6)"

check "t3 command exists globally" test -x /usr/local/bin/t3
check "t3 version works as service user" env HOME="${T3_HOME}" /usr/local/bin/t3 --version
check "t3 installation is root-owned" test "$(stat -c %U /usr/local/lib/node_modules/t3)" = root
check "t3 is not installed in the service user's local bin" test ! -e "${T3_HOME}/.local/bin/t3"
check "codex is not installed" bash -c "! command -v codex >/dev/null 2>&1"
# shellcheck disable=SC2016
check "launcher uses the service base directory" grep -q -- '--base-dir "${HOME}/.t3"' /usr/local/bin/t3code-server
check "launcher execs the platform binary rather than the t3 shim" bash -c '
    executable="$(node /usr/local/lib/t3code-server/resolve-executable.cjs /usr/local/lib/node_modules/t3 /usr/local/bin/t3)"
    [ "${executable}" != /usr/local/bin/t3 ] && [ -x "${executable}" ]
'
check "s6 service is registered" test -f /etc/s6-overlay/user-bundles.d/user/contents.d/t3code-server
check "s6 service is a longrun" grep -qx longrun /etc/s6-overlay/s6-rc.d/t3code-server/type
check "SSH agent linker is absent" test ! -e /usr/local/bin/t3code-ssh-agent-link
check "SSH agent linker service is absent" test ! -e /etc/s6-overlay/s6-rc.d/t3code-ssh-agent-link
check "T3 has no SSH agent linker dependency" test ! -e /etc/s6-overlay/s6-rc.d/t3code-server/dependencies.d/t3code-ssh-agent-link
check "T3 does not override SSH_AUTH_SOCK" bash -c "! grep -q 'SSH_AUTH_SOCK' /etc/s6-overlay/s6-rc.d/t3code-server/run"
check "systemd unit is absent" test ! -e /etc/systemd/system/t3code.service

reportResults
