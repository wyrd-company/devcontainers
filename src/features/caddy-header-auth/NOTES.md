Runs a Unix-socket `forward_auth` server under [s6-overlay](https://github.com/just-containers/s6-overlay) that executes root-registered header-helper commands from `/etc/caddy-header-auth/conf.d/*.json` and returns their JSON headers to [Caddy](https://caddyserver.com/). The service runs as `serviceUser` (`vscode` by default) and creates its socket directory as `2750 <serviceUser>:<socketGroup>` (`caddy` when present), so Caddy can reach `/run/caddy-header-auth/auth.sock` without joining the service user's groups.

When the [Ansible](https://www.ansible.com/) Feature is installed, `caddy-header-auth` starts only after the `ansible-setup` s6-rc oneshot finishes, and does not start if it fails. Without Ansible, startup does not change.

## Trademarks

This feature is not affiliated with or endorsed by Stack Holdings GmbH. Caddy and its logo are trademarks of Stack Holdings GmbH. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature integrates with.

Logo: the Caddy icon from [logo-light.svg](https://github.com/caddyserver/website/blob/a49be19b2ec650b98852341775f609444650749c/src/resources/images/logo-light.svg), without the wordmark.
