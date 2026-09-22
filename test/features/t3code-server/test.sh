#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

T3_HOME="$(getent passwd vscode | cut -d: -f6)"
RUNTIME="${T3_HOME}/.t3/runtime"
selected="$(/usr/local/lib/t3code-server/t3code-runtime selected-version)"

check "t3 command exists globally" test -x /usr/local/bin/t3
check "t3 version works as service user" env HOME="${T3_HOME}" /usr/local/bin/t3 --version
check "a version is selected for the service" test -n "${selected}"
check "selected runtime is completely installed" /usr/local/lib/t3code-server/t3code-runtime installed "${selected}"
check "selected runtime executable is present" test -x "${RUNTIME}/versions/${selected}/t3"
check "selected runtime is owned by the service user" test "$(stat -c %U "${RUNTIME}/versions/${selected}/t3")" = vscode
check "selected version file names the selected version" test "$(cat "${RUNTIME}/selected-version")" = "${selected}"
check "t3 runs the selected runtime" test "$(env HOME="${T3_HOME}" /usr/local/bin/t3 --version)" = "t3 v${selected}"
check "update command is installed" test -x /usr/local/bin/t3code-server-update
check "update command reports status without sudo" bash -c "/usr/local/bin/t3code-server-update --status | grep -q 'selected version: ${selected}'"
check "sudo grant for the update command is installed" test -f /etc/sudoers.d/t3code-server
check "service user may sudo the update command" sudo -n -l /usr/local/bin/t3code-server-update
check "service user may sudo the update command with arguments" sudo -n -l /usr/local/bin/t3code-server-update --status
check "sudoers grant is valid" sudo -n /usr/local/bin/t3code-server-update --status
check "codex is not installed" bash -c "! command -v codex >/dev/null 2>&1"
# shellcheck disable=SC2016
check "service wrapper uses the service base directory" grep -q -- '--base-dir "${HOME}/.t3"' /usr/local/bin/t3code-server
check "service wrapper runs the selected runtime" grep -q 't3code-runtime selected-entry' /usr/local/bin/t3code-server
check "s6 service is registered" test -f /etc/s6-overlay/user-bundles.d/user/contents.d/t3code-server
check "s6 service is a longrun" grep -qx longrun /etc/s6-overlay/s6-rc.d/t3code-server/type
check "SSH agent linker is absent" test ! -e /usr/local/bin/t3code-ssh-agent-link
check "SSH agent linker service is absent" test ! -e /etc/s6-overlay/s6-rc.d/t3code-ssh-agent-link
check "T3 has no SSH agent linker dependency" test ! -e /etc/s6-overlay/s6-rc.d/t3code-server/dependencies.d/t3code-ssh-agent-link
check "T3 does not override SSH_AUTH_SOCK" bash -c "! grep -q 'SSH_AUTH_SOCK' /etc/s6-overlay/s6-rc.d/t3code-server/run"
check "systemd unit is absent" test ! -e /etc/systemd/system/t3code.service

reportResults
