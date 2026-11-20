#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

FEATURE_USER=root
if id -u vscode >/dev/null 2>&1; then
    FEATURE_USER=vscode
fi
USER_HOME="$(getent passwd "${FEATURE_USER}" | cut -d: -f6)"
AGY="${USER_HOME}/.local/bin/agy"

check "agy command exists" test -x "${AGY}"
check "agy version works as user" env HOME="${USER_HOME}" "${AGY}" --version
check "agy executable is user-owned" test "$(stat -c %U "$(readlink -f "${AGY}")")" = "${FEATURE_USER}"
check "user local directory is user-owned" test "$(stat -c %U "${USER_HOME}/.local")" = "${FEATURE_USER}"
check "global agy command is only a symlink" test -L /usr/local/bin/agy
check "global agy command targets the user installation" test "$(readlink -f /usr/local/bin/agy)" = "$(readlink -f "${AGY}")"
check "installer did not edit shell profiles" bash -c "! grep -qs -i antigravity '${USER_HOME}/.bashrc' '${USER_HOME}/.profile' '${USER_HOME}/.zshrc'"

reportResults
