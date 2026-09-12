#!/usr/bin/env bash

set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

FEATURE_USER=root
if id -u vscode >/dev/null 2>&1; then
    FEATURE_USER=vscode
fi
USER_HOME="$(getent passwd "${FEATURE_USER}" | cut -d: -f6)"
CODEX="${USER_HOME}/.local/bin/codex"

check "codex command exists" test -x "${CODEX}"
check "codex version works as user" env HOME="${USER_HOME}" "${CODEX}" --version
check "codex executable is user-owned" test "$(stat -c %U "$(readlink -f "${CODEX}")")" = "${FEATURE_USER}"
check "codex package is user-owned" test "$(stat -c %U "${USER_HOME}/.local/lib/node_modules/@openai/codex")" = "${FEATURE_USER}"
# shellcheck disable=SC2016
check "node major is 24" bash -c 'test "$(node -p "process.versions.node.split(\".\")[0]")" = 24'

schema_dir="$(mktemp -d)"
check "codex app-server schema generation works" env HOME="${USER_HOME}" "${CODEX}" app-server generate-json-schema --out "${schema_dir}"
check "codex thread start schema exists" test -s "${schema_dir}/v2/ThreadStartParams.json"

reportResults
