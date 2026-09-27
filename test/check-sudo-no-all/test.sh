#!/usr/bin/env bash
#
# Regression test for scripts/check-sudo-no-all.sh. Builds sample images on top of
# BASE and asserts that each grant is rejected or accepted as expected.

set -euo pipefail

base="${1:?usage: test.sh BASE_IMAGE}"
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
check="${repo_root}/scripts/check-sudo-no-all.sh"
tag="check-sudo-no-all-sample:${RANDOM}"
build_dir="$(mktemp -d)"

cleanup() {
    docker image rm --force "${tag}" >/dev/null 2>&1 || true
    rm -rf "${build_dir}"
}
trap cleanup EXIT

# Each case is "<expected> <shell command run as root in the sample image>".
cases=(
    'reject echo "vscode ALL=(root) NOPASSWD: ALL" >/etc/sudoers.d/sample-feature'
    'reject echo "vscode ALL=(root) NOPASSWD: ALL" >>/etc/sudoers.d/vscode'
    'reject usermod -aG sudo vscode'
    'reject printf "Cmnd_Alias SAMPLE = ALL\nvscode ALL=(root) NOPASSWD: SAMPLE\n" >/etc/sudoers.d/sample-feature'
    'reject echo "vscode ALL=(root) NOPASSWD: /usr/bin/*" >/etc/sudoers.d/sample-feature'
    'reject echo "vscode ALL=(root) NOPASSWD: /home/vscode/*" >/etc/sudoers.d/sample-feature'
    'reject echo "vscode ALL=(root) NOPASSWD: /bin/bash" >/etc/sudoers.d/sample-feature'
    'reject echo "vscode ALL=(root) NOPASSWD: /bin/sh -c *" >/etc/sudoers.d/sample-feature'
    'reject echo "vscode ALL=(root) NOPASSWD: /usr/bin/env *" >/etc/sudoers.d/sample-feature'
    'reject echo "vscode ALL=(www-data) NOPASSWD: ALL" >/etc/sudoers.d/sample-feature'
    'reject echo "vscode ALL=(:adm) NOPASSWD: ALL" >/etc/sudoers.d/sample-feature'
    'accept echo "vscode ALL=(root) NOPASSWD: /usr/bin/passwd vscode" >/etc/sudoers.d/sample-feature'
    'accept true'
)

for case in "${cases[@]}"; do
    expected="${case%% *}"
    setup="${case#* }"
    printf 'FROM %s\nUSER root\nRUN %s && chmod 0440 /etc/sudoers.d/*\n' "${base}" "${setup}" \
        >"${build_dir}/Dockerfile"
    docker build --quiet --tag "${tag}" "${build_dir}" >/dev/null
    if "${check}" "${tag}" >/dev/null 2>&1; then
        actual=accept
    else
        actual=reject
    fi
    if [ "${actual}" != "${expected}" ]; then
        echo "Expected the check to ${expected}, but it did ${actual}: ${setup}" >&2
        exit 1
    fi
    echo "${expected}: ${setup}"
done
