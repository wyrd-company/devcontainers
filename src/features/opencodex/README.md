# OpenCodex

Installs [OpenCodex](https://github.com/lidge-jun/opencodex) (`ocx`) for the service user and runs `ocx start` as a native s6-overlay 3 service. The proxy and its web dashboard listen on a loopback port. The installation and all runtime state are owned by the service user rather than root.

The Feature requires a Debian/Ubuntu image with s6-overlay 3 already installed. Node.js 24 is supplied through the official Dev Container Node Feature.

## Options

| Option        | Type   | Default     | Description                                                                                                                                       |
| ------------- | ------ | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `version`     | string | `latest`    | OpenCodex npm version or dist-tag, such as `latest`, `preview`, or `2.51.0`.                                                                      |
| `port`        | string | `10100`     | Loopback port the proxy and dashboard listen on.                                                                                                  |
| `serviceUser` | string | `automatic` | User account that owns the installation and runs the service. Automatic selection prefers the remote user, container user, `vscode`, then `root`. |
| `dnsName`     | string | `""`        | Optional fully qualified DNS name that exposes the dashboard through the Caddy Feature.                                                           |

## Example usage

```json
{
  "image": "ghcr.io/wyrd-company/devcontainers/base:noble",
  "overrideCommand": false,
  "features": {
    "ghcr.io/wyrd-company/devcontainers/opencodex:1": {}
  }
}
```

To pin a release and expose the dashboard through Caddy:

```json
{
  "image": "ghcr.io/wyrd-company/devcontainers/base:noble",
  "overrideCommand": false,
  "features": {
    "ghcr.io/wyrd-company/devcontainers/caddy:1": {},
    "ghcr.io/wyrd-company/devcontainers/opencodex:1": {
      "version": "2.51.0",
      "dnsName": "ocx.dev-environment.example.test"
    }
  }
}
```

## Layout

| Path                                                 | Owner        | Purpose                                                                            |
| ---------------------------------------------------- | ------------ | ---------------------------------------------------------------------------------- |
| `<home>/.opencodex`                                  | service user | OpenCodex state: `config.json`, provider logins, admin token, logs, pid files.     |
| `<home>/.local/lib/node_modules/@bitkyc08/opencodex` | service user | The installed package. `ocx update` stages and swaps it here.                      |
| `<home>/.local/bin/ocx`                              | service user | The npm launcher for the installed package.                                        |
| `/usr/local/bin/ocx`, `/usr/local/bin/opencodex`     | root         | System-wide entry points. They run the user-owned launcher.                        |
| `/usr/local/bin/opencodex-service`                   | root         | The s6 launcher. It runs `ocx start --port <port>` as the service user.            |
| `/run/opencodex/paused`                              | service user | Operator hold. While present, the s6 launcher waits instead of starting the proxy. |
| `/run/opencodex/holds/<pid>`                         | service user | Hold owned by a running `ocx update`. Ignored once that process is gone.           |
| `/run/opencodex/update.lock`                         | service user | Lock that serializes `ocx update` runs.                                            |

## Persistent state

The Feature creates no mounts. Mount `<home>/.opencodex` to keep OpenCodex configuration and state across container rebuilds:

```json
{
  "mounts": [
    "source=opencodex-state,target=/home/vscode/.opencodex,type=volume"
  ]
}
```

Replace `vscode` and its home directory when `serviceUser` resolves to another account. OpenCodex also writes into the service user's Codex, Claude Code, and Grok configuration when it starts and stops. Mount those directories, such as `<home>/.codex`, when the paired tools should keep their state as well.

Do not mount over `<home>/.local`. The package lives there in the image layer, and an empty bind mount hides it. A version installed with `ocx update` lasts until the container is rebuilt; set `version` to keep it.

## Service behavior

The service runs `ocx start --port <port>` with `OCX_SERVICE=1`. OpenCodex injects the proxy address into the service user's Codex configuration on every start. `ocx stop` stops the proxy and restores the native Codex configuration; s6 then starts the proxy again. To hold the proxy down, create `/run/opencodex/paused` before running `ocx stop`, and remove the file to resume.

The service does not depend on `ocx init`. Configure providers through the dashboard, or headlessly with `ocx provider add` as the service user. Run `ocx` commands as the service user so they find the same `OPENCODEX_HOME`.

## Updating

Run `ocx update` as the service user. The system `ocx` wrapper takes `/run/opencodex/update.lock` and writes a hold file named after its own process id under `/run/opencodex/holds`. OpenCodex stops the proxy, stages the new package beside the installed one, swaps it in, and exits. The wrapper then removes its hold and s6 starts the proxy on the new version. A second `ocx update` exits while the lock is held. The launcher ignores a hold whose process no longer exists, so an interrupted update cannot leave the proxy down. An operator hold in `/run/opencodex/paused` is independent: the proxy stays down after the update until that file is removed.

```bash
ocx update
ocx update --tag preview
```

`ocx update` runs npm as the service user, so it does not require root.

## Caddy

When both Features are selected, OpenCodex installs after Caddy automatically. Setting `dnsName` writes `/etc/caddy/conf.d/opencodex.caddy` and registers the name in `/etc/caddy/required-hosts.d/opencodex.host`. Caddy waits for that name to resolve before requesting its certificate, then serves it over HTTPS and proxies to the dashboard on the configured loopback port. Installation fails when `dnsName` is set without a Caddy Feature version that supports DNS readiness.

OpenCodex admits management requests only with a loopback `Host` header and a loopback or absent `Origin` header. The fragment presents the upstream loopback `Host` and rewrites the dashboard's own `Origin` (`https://<dnsName>`) to the loopback origin. Any other `Origin` passes through unchanged and OpenCodex refuses it.

The proxy keeps its loopback bind, so it treats every request that arrives through Caddy as local. Anyone who can reach `https://<dnsName>` can use the dashboard without a token. Limit who can resolve and reach the name.
