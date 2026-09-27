#!/usr/bin/env bash
#
# Fails when any non-root user in IMAGE may run an arbitrary command through sudo.
#
# The check asks sudo itself, so aliases, group rules, wildcards, and rule order
# are resolved the way sudo resolves them at runtime. It checks the image exactly
# as built. Test images must therefore be built on the base image from the same
# checkout (see build-base-image.sh), not on the last published one.
#
# For every non-root user that holds any sudo privilege, it asks whether that
# user may run, as any user or group:
#   - a probe command that no rule names, placed in every executable directory,
#     every home directory, /opt, and /tmp, which catches ALL and directory
#     wildcards such as /usr/bin/*;
#   - every login shell and env, which run arbitrary commands.

set -euo pipefail

image="${1:?usage: check-sudo-no-all.sh IMAGE}"

docker run --rm --user root --entrypoint /bin/sh "${image}" -c '
    set -eu
    if ! command -v sudo >/dev/null 2>&1; then
        echo "sudo is not installed; nothing to check."
        exit 0
    fi

    probe_name="sudo-all-probe-$$"
    commands=""
    homes="$(getent passwd | cut -d: -f6 | sort -u)"
    for dir in /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin \
        /usr/libexec /usr/lib /command /opt /tmp ${homes}; do
        [ -d "${dir}" ] || continue
        probe="${dir%/}/${probe_name}"
        if [ ! -e "${probe}" ]; then
            printf "#!/bin/sh\n" >"${probe}"
            chmod 0755 "${probe}"
        fi
        commands="${commands} ${probe}"
    done
    for shell in $(grep "^/" /etc/shells) /usr/bin/env; do
        [ -x "${shell}" ] && commands="${commands} ${shell}"
    done

    runas_users="$(getent passwd | cut -d: -f1)"
    runas_groups="$(getent group | cut -d: -f1)"
    failed=0
    for user in $(getent passwd | awk -F: "\$3 != 0 { print \$1 }"); do
        if ! LC_ALL=C sudo -n -l -U "${user}" 2>/dev/null | grep -q "may run the following commands"; then
            continue
        fi
        for command in ${commands}; do
            for target in ${runas_users}; do
                if sudo -n -l -U "${user}" -u "${target}" "${command}" >/dev/null 2>&1; then
                    echo "sudo lets ${user} run ${command} as user ${target}." >&2
                    failed=1
                fi
            done
            for group in ${runas_groups}; do
                if sudo -n -l -U "${user}" -g "${group}" "${command}" >/dev/null 2>&1; then
                    echo "sudo lets ${user} run ${command} as group ${group}." >&2
                    failed=1
                fi
            done
        done
        if [ "${failed}" -ne 0 ]; then
            sudo -n -l -U "${user}" >&2 || true
            exit 1
        fi
    done
'
echo "No user has unrestricted sudo in ${image}."
