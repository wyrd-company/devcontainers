#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

require_root

devcontainer_user="$(pick_devcontainer_user)"
user_home="$(user_home_dir "${devcontainer_user}")"
[ -n "${user_home}" ] || err "Unable to resolve the home directory for ${devcontainer_user}."

install -d -m 0755 -o "${devcontainer_user}" -g "$(id -gn "${devcontainer_user}")" "${user_home}/.local"

package_spec="@earendil-works/pi-coding-agent@${VERSION}"
log "Installing ${package_spec} for ${devcontainer_user}"
# Pi does not require install scripts for normal npm installs.
run_as_user "${devcontainer_user}" env \
    HOME="${user_home}" \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    npm install --global --ignore-scripts --prefix "${user_home}/.local" "${package_spec}"

pi_binary="${user_home}/.local/bin/pi"
[ -x "${pi_binary}" ] || err "Pi CLI was not installed at ${pi_binary}."
ln -sf "${pi_binary}" /usr/local/bin/pi

log "Installed Pi CLI $(run_as_user "${devcontainer_user}" env HOME="${user_home}" "${pi_binary}" --version)"
