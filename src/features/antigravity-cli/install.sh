#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

require_root
ensure_apt_packages ca-certificates curl

devcontainer_user="$(pick_devcontainer_user)"
user_home="$(user_home_dir "${devcontainer_user}")"
[ -n "${user_home}" ] || err "Unable to resolve the home directory for ${devcontainer_user}."

install -d -m 0755 -o "${devcontainer_user}" -g "$(id -gn "${devcontainer_user}")" \
    "${user_home}/.local" "${user_home}/.local/bin"

installer="$(mktemp)"
scratch_home="$(mktemp -d)"
trap 'rm -rf "${installer}" "${scratch_home}"' EXIT
chown "${devcontainer_user}:$(id -gn "${devcontainer_user}")" "${scratch_home}"
curl --fail --location --silent --show-error https://antigravity.google/cli/install.sh --output "${installer}"
chmod 0755 "${installer}"

# The installer takes no version: it installs the latest build, verified against the SHA-512 in Google's
# release manifest, and the CLI then updates itself in place. Run it with a scratch HOME and --dir so the
# installer's `agy install` step never edits the user's shell profiles; the dotfiles own those.
log "Installing Antigravity CLI for ${devcontainer_user}"
run_as_user "${devcontainer_user}" env HOME="${scratch_home}" PATH="${user_home}/.local/bin:${PATH}" SHELL= \
    bash "${installer}" --dir "${user_home}/.local/bin"

agy_binary="${user_home}/.local/bin/agy"
[ -x "${agy_binary}" ] || err "Antigravity CLI was not installed at ${agy_binary}."
ln -sf "${agy_binary}" /usr/local/bin/agy

log "Installed Antigravity CLI $(run_as_user "${devcontainer_user}" env HOME="${user_home}" "${agy_binary}" --version)"
