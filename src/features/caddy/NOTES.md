Caddy runs as the package-provided `caddy` user. Add reverse-proxy site blocks as `.caddy` files beneath `/etc/caddy/conf.d`; the s6-supervised watcher applies valid changes without restarting the container. Register DNS names required for automatic HTTPS in `/etc/caddy/required-hosts.d/*.host`; Caddy waits for them to resolve before startup and reload.

## Trademarks

This feature is not affiliated with or endorsed by Stack Holdings GmbH. Caddy and its logo are trademarks of Stack Holdings GmbH. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the Caddy icon from [logo-light.svg](https://github.com/caddyserver/website/blob/a49be19b2ec650b98852341775f609444650749c/src/resources/images/logo-light.svg), without the wordmark. Caddy is a registered trademark of Stack Holdings GmbH; the Caddy brand kit allows its use, unmodified and without implied endorsement.
