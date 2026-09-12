# OpenCodex

Installs [OpenCodex](https://github.com/lidge-jun/opencodex) (`ocx`) for the service user. The default `client` mode connects local coding tools to an external Remote Hub. Optional `standalone` mode runs a local proxy and dashboard as a native s6-overlay 3 service.

The Feature requires a Debian/Ubuntu image with s6-overlay 3 already installed. Node.js 24 is supplied through the official Dev Container Node Feature.

Version 2 defaults to client mode. Version 1 ran a local proxy by default. Set `mode` to `standalone` to keep that behavior when moving from version 1.

## Options

| Option        | Type   | Default     | Description                                                                                                                                       |
| ------------- | ------ | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `mode`        | string | `client`    | `client` refreshes a persisted Remote Hub connection at startup. `standalone` runs a local proxy and dashboard.                                   |
| `version`     | string | `latest`    | OpenCodex npm version or dist-tag, such as `latest`, `preview`, or `2.51.0`.                                                                      |
| `port`        | string | `10100`     | Loopback port for the standalone proxy and dashboard. Ignored in client mode.                                                                     |
| `serviceUser` | string | `automatic` | User account that owns the installation and runs OpenCodex. Automatic selection prefers the remote user, container user, `vscode`, then `root`.   |
| `dnsName`     | string | `""`        | Optional fully qualified DNS name for the standalone dashboard. Requires the Caddy Feature and `mode=standalone`.                                 |

## Remote Hub client

Persist separate OpenCodex and Codex homes for each dev container:

```json
{
  "image": "ghcr.io/wyrd-company/devcontainers/base:noble",
  "overrideCommand": false,
  "features": {
    "ghcr.io/wyrd-company/devcontainers/opencodex:2": {}
  },
  "mounts": [
    "source=opencodex-client-state,target=/home/vscode/.opencodex,type=volume",
    "source=codex-client-state,target=/home/vscode/.codex,type=volume"
  ]
}
```

Each concurrent client needs its own `.opencodex` directory and Codex home. Do not share either directory between active dev containers.

The Feature does not enroll a client because Remote Hub pairing authority is transient. Enroll the container once after its persistent mounts are ready:

```bash
ocx connect https://service.example.test --pairing-code-stdin
```

On later starts, an s6 oneshot checks the persisted connection. It runs `ocx sync` only when the client is connected and this container owns its saved connection token. A disconnected, changed, or failed client does not block container startup. `ocx sync` refreshes the hub catalog and reapplies the Codex client configuration; provider credentials and routing stay on the hub.

## Standalone mode

Set `mode` to `standalone` to run the proxy and dashboard inside the dev container:

```json
{
  "image": "ghcr.io/wyrd-company/devcontainers/base:noble",
  "overrideCommand": false,
  "features": {
    "ghcr.io/wyrd-company/devcontainers/caddy:1": {},
    "ghcr.io/wyrd-company/devcontainers/opencodex:2": {
      "mode": "standalone",
      "version": "2.51.0",
      "dnsName": "service.example.test"
    }
  }
}
```

The service runs `ocx start --port <port>` with `OCX_SERVICE=1`. Configure providers through the dashboard or with `ocx provider add` as the service user.

## Persistent state

The Feature creates no mounts. Replace `vscode` and its home directory when `serviceUser` resolves to another account. Do not mount over `<home>/.local`; the installed package lives there in the image layer.

OpenCodex state is in `<home>/.opencodex`. OpenCodex also writes client configuration into tool-specific homes, such as `<home>/.codex`. Persist those homes when the tool configuration must survive a rebuild.

## Layout

| Path                                                 | Mode       | Owner        | Purpose                                                                            |
| ---------------------------------------------------- | ---------- | ------------ | ---------------------------------------------------------------------------------- |
| `<home>/.opencodex`                                  | both       | service user | OpenCodex client or standalone state.                                              |
| `<home>/.local/lib/node_modules/@bitkyc08/opencodex` | both       | service user | Installed package.                                                                |
| `<home>/.local/bin/ocx`                              | both       | service user | npm launcher for the installed package.                                            |
| `/usr/local/bin/ocx`, `/usr/local/bin/opencodex`     | both       | root         | System-wide entry points for the user-owned launcher.                              |
| `/usr/local/bin/opencodex-client-sync`               | client     | root         | Non-blocking startup synchronization.                                              |
| `/usr/local/bin/opencodex-service`                   | standalone | root         | s6 launcher for `ocx start --port <port>`.                                         |
| `/run/opencodex/paused`                              | standalone | service user | Operator hold. While present, the launcher waits before starting the proxy.        |
| `/run/opencodex/holds/<pid>`                         | standalone | service user | Hold owned by a running `ocx update`; stale holds are ignored.                     |
| `/run/opencodex/update.lock`                         | standalone | service user | Lock that serializes `ocx update` runs.                                            |

## Updating

In client mode, `ocx update` runs the user-owned installation directly. In standalone mode, the system wrapper serializes updates and holds the supervised proxy while OpenCodex replaces the package. The proxy resumes on the new version after the update. Both modes update without root.

## Caddy

`dnsName` applies only to standalone mode. When both Features are selected, OpenCodex installs after Caddy. The Feature writes `/etc/caddy/conf.d/opencodex.caddy` and registers the name in `/etc/caddy/required-hosts.d/opencodex.host`.

OpenCodex accepts management requests only with a loopback `Host` and a loopback or absent `Origin`. The Caddy fragment supplies the loopback `Host` and rewrites the dashboard's own origin to the loopback origin. Other origins pass through and OpenCodex rejects them.

The proxy keeps its loopback bind, so it treats requests through Caddy as local. Anyone who can reach the configured HTTPS name can use the dashboard without a token. Limit who can resolve and reach the name.
