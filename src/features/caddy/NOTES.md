[Caddy](https://caddyserver.com/) runs as the package-provided `caddy` user. Add reverse-proxy site blocks as `.caddy` files beneath `/etc/caddy/conf.d`; the [s6-overlay](https://github.com/just-containers/s6-overlay)-supervised watcher applies valid changes without restarting the container. Register DNS names required for automatic HTTPS in `/etc/caddy/required-hosts.d/*.host`; Caddy waits for them to resolve before startup and reload.

When the [Ansible](https://www.ansible.com/) Feature is installed, the `caddy` service starts only after the `ansible-setup` s6-rc oneshot finishes, and does not start if it fails. Without Ansible, startup does not change. The config watcher starts after Caddy, so it also waits.

## Trademarks

This feature is not affiliated with or endorsed by Stack Holdings GmbH. Caddy and its logo are trademarks of Stack Holdings GmbH. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the Caddy icon from [logo-light.svg](https://github.com/caddyserver/website/blob/a49be19b2ec650b98852341775f609444650749c/src/resources/images/logo-light.svg), without the wordmark.
