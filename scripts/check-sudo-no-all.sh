#!/usr/bin/env bash
#
# Fails when any non-root user in IMAGE may run an arbitrary command through sudo.
#
# The check asks sudo itself, so aliases, group rules, wildcards, and rule order
# are all resolved the way sudo resolves them at runtime. It runs a command that
# no rule should name, from a random path. A user who may run it has ALL or an
# equivalent wildcard.
#
# The base image's vscode policy from this checkout is mounted over the image's
# copy, so a Feature is checked against the base from the same commit rather
# than the last published one.

set -euo pipefail

image="${1:?usage: check-sudo-no-all.sh IMAGE}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
base_policy="${repo_root}/src/images/base-ubuntu/sudoers.d/vscode"

docker run --rm \
    --user root \
    --entrypoint /bin/sh \
    --mount "type=bind,source=${base_policy},target=/etc/sudoers.d/vscode,readonly" \
    "${image}" -c '
        set -eu
        if ! command -v sudo >/dev/null 2>&1; then
            echo "sudo is not installed; nothing to check."
            exit 0
        fi
        probe="/opt/sudo-all-probe-$$"
        printf "#!/bin/sh\n" >"${probe}"
        chmod 0755 "${probe}"
        failed=0
        for user in $(getent passwd | awk -F: "\$3 != 0 { print \$1 }"); do
            if sudo -n -l -U "${user}" "${probe}" >/dev/null 2>&1; then
                echo "sudo grants ${user} ALL or an equivalent wildcard:" >&2
                sudo -n -l -U "${user}" >&2 || true
                failed=1
            fi
        done
        rm -f "${probe}"
        exit "${failed}"
    '
echo "No user has unrestricted sudo in ${image}."
