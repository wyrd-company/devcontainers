# Caddy Header Auth

Runs a local Unix-socket `forward_auth` server under [s6-overlay](https://github.com/just-containers/s6-overlay) that executes root-registered header-helper commands and returns their JSON headers to [Caddy](https://caddyserver.com/).

This lets a local Caddy reverse proxy inject dynamic credentials (such as bearer tokens read on demand by a CLI helper) for clients that only support static HTTP endpoints.

The Feature requires a Debian/Ubuntu image with s6-overlay 3 already installed and supports `amd64` and `arm64`.

## How it works

Each route is a root-owned JSON file under `/etc/caddy-header-auth/conf.d/<route>.json`:

```json
{
  "command": ["/usr/local/bin/sample-headers"]
}
```

Optional fields:

- `env`: object of extra environment variables merged on top of the service's environment.
- `timeout`: positive number of seconds (up to `300`) overriding the service's default timeout for that route.

When Caddy sends `GET /<route>` over `/run/caddy-header-auth/auth.sock`, the service executes `command` directly (without a shell) as `serviceUser`, parses stdout as a non-empty JSON object of `{"Header-Name": "value"}` pairs, validates the header names and values, and replies `200 OK` with those headers and `Cache-Control: no-store`. Route files are read on each request, so added, changed, or removed routes take effect without a restart.

If the helper fails, times out, or prints invalid or empty JSON, the service returns `502` or `504` so Caddy does not forward an unauthenticated request upstream. Helper stdout and stderr are never logged.

## Well-known locations

| Purpose | Default location |
| --- | --- |
| Route definitions | `/etc/caddy-header-auth/conf.d/*.json` |
| Unix socket | `/run/caddy-header-auth/auth.sock` |
| Service launcher | `/usr/local/bin/caddy-header-auth-service` |

## Caddy integration

When the [Caddy](https://caddyserver.com/) Feature is installed alongside this Feature, `socketGroup` defaults to `caddy`. The socket directory is created `2750 <serviceUser>:caddy`, so Caddy can connect to `/run/caddy-header-auth/auth.sock` without joining the service user's groups.

Place a loopback site block under `/etc/caddy/system.d/`:

```caddyfile
http://127.0.0.1:18317 {
    bind 127.0.0.1

    handle /mcp {
        forward_auth unix//run/caddy-header-auth/auth.sock {
            uri /sample-route
            copy_headers Authorization
        }

        reverse_proxy https://upstream.example.test {
            flush_interval -1
        }
    }

    handle {
        respond 404
    }
}
```

Always include `bind 127.0.0.1` so the listener is restricted to IPv4 loopback rather than all container interfaces.

## Options

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `serviceUser` | string | `automatic` | User that runs the service and executes header-helper commands. `automatic` selects the remote user, container user, `vscode`, then `root`. |
| `socketGroup` | string | `automatic` | Group granted access to the Unix socket directory. `automatic` selects `caddy` when present, otherwise the primary group of `serviceUser`. |
| `socketPath` | string | `/run/caddy-header-auth/auth.sock` | Absolute path of the Unix domain socket. |
| `configDir` | string | `/etc/caddy-header-auth/conf.d` | Absolute directory containing route JSON files. |
| `timeoutSeconds` | string | `10` | Default per-request timeout in seconds for each helper invocation (`1` to `300`). |

## Example

```json
{
  "image": "ghcr.io/wyrd-company/devcontainers/base:noble",
  "features": {
    "ghcr.io/wyrd-company/devcontainers/caddy:1": {},
    "ghcr.io/wyrd-company/devcontainers/caddy-header-auth:1": {}
  }
}
```

## Ansible

When the [Ansible](https://www.ansible.com/) Feature is installed, the `caddy-header-auth` service starts only after the `ansible-setup` s6-rc oneshot finishes. If the oneshot fails, the service does not start. This Feature declares `installsAfter` for the Ansible Feature, so that the `ansible-setup` service definition exists when this installer runs. The installer adds the dependency only when that definition exists. Without Ansible, startup does not change.

## Trademarks

This feature is not affiliated with or endorsed by Stack Holdings GmbH. Caddy and its logo are trademarks of Stack Holdings GmbH. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature integrates with.

Logo: the Caddy icon from [logo-light.svg](https://github.com/caddyserver/website/blob/a49be19b2ec650b98852341775f609444650749c/src/resources/images/logo-light.svg), without the wordmark.
