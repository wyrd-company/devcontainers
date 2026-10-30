# Caddy Reverse Proxy

Installs [Caddy](https://caddyserver.com/)'s official Debian package from the GitHub release, verified against the release's SHA-512 checksums, and supervises it with [s6-overlay](https://github.com/just-containers/s6-overlay). A second s6 service watches a well-known fragment directory and gracefully reloads valid configuration changes through a permissioned Unix admin socket.

The Feature requires a Debian/Ubuntu image with s6-overlay 3 already installed.

## Well-known locations

| Purpose            | Location                             |
| ------------------ | ------------------------------------ |
| Main Caddyfile     | `/etc/caddy/Caddyfile`               |
| Proxy fragments    | `/etc/caddy/conf.d/*.caddy`          |
| Required DNS names | `/etc/caddy/required-hosts.d/*.host` |
| Admin API socket   | `/run/caddy/admin.sock`              |
| Reload command     | `/usr/local/bin/caddy-reload`        |

The selected configuration user can add, change, and remove fragments without root access. The watcher validates the complete Caddyfile before reloading; a failed reload leaves the active configuration intact.

Integrations that require automatic HTTPS should place each required DNS name on its own line in a `.host` file under `/etc/caddy/required-hosts.d`. Caddy waits for every registered name to resolve before initial startup and before hot reloads, preventing ACME validation from racing service discovery.

## Options

| Option       | Type   | Default     | Description                                                                                  |
| ------------ | ------ | ----------- | -------------------------------------------------------------------------------------------- |
| `version`    | string | `latest`    | Stable Caddy release version, such as `2.11.4`.                                              |
| `acmeCa`     | string | `""`        | Optional ACME directory URL for automatic HTTPS.                                             |
| `acmeCaRoot` | string | `""`        | Optional in-container path to the public CA root certificate protecting the ACME endpoint.   |
| `configUser` | string | `automatic` | User allowed to manage fragments. Automatic selection prefers the Dev Container remote user. |

## Example

```json
{
  "image": "ghcr.io/wyrd-company/devcontainers/base:noble",
  "features": {
    "ghcr.io/wyrd-company/devcontainers/caddy:1": {
      "acmeCa": "https://acme.example.com/acme/local/directory",
      "acmeCaRoot": "/usr/local/share/ca-certificates/caddy-root.crt"
    }
  }
}
```

The root path refers to a public certificate, never the CA private key. It may be omitted when the CA is already trusted through the container's system trust store.

## Ansible

When the [Ansible](https://www.ansible.com/) Feature is installed, the `caddy` service starts only after the `ansible-setup` s6-rc oneshot finishes. If the oneshot fails, the `caddy` service does not start. This Feature declares `installsAfter` for the Ansible Feature, so that the `ansible-setup` service definition exists when this installer runs. The installer adds the dependency only when that definition exists. Without Ansible, startup does not change. The config watcher starts after Caddy, so it also waits.

## Trademarks

This feature is not affiliated with or endorsed by Stack Holdings GmbH. Caddy and its logo are trademarks of Stack Holdings GmbH. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the Caddy icon from [logo-light.svg](https://github.com/caddyserver/website/blob/a49be19b2ec650b98852341775f609444650749c/src/resources/images/logo-light.svg), without the wordmark.
