# OpenBao Agent

Installs the official OpenBao `bao` binary and runs `bao agent` as an s6-overlay longrun service. The Feature requires a Debian/Ubuntu image with s6-overlay 3 and supports `amd64` and `arm64`.

OpenBao Agent runs as the selected devcontainer user so that authentication inputs, rendered templates, and token sinks use that user's permissions. Automatic selection prefers the remote user, container user, `vscode`, then `root`.

## Configuration

The Feature does not create an Agent configuration or choose an authentication method. Supply the configuration as a read-only mount at `/etc/openbao/agent.hcl`:

```json
{
  "image": "ghcr.io/wyrd-company/devcontainers/base:noble",
  "overrideCommand": false,
  "features": {
    "ghcr.io/wyrd-company/devcontainers/openbao-agent:1": {}
  },
  "mounts": [
    "source=${localWorkspaceFolder}/.devcontainer/openbao-agent.hcl,target=/etc/openbao/agent.hcl,type=bind,readonly"
  ]
}
```

The service fails closed when the configuration is absent or unreadable. The file and every authentication input it references must be readable by `serviceUser`. Template destinations and token sinks must be writable by that user.

Use `configPath` when the configuration must be mounted elsewhere:

```json
{
  "features": {
    "ghcr.io/wyrd-company/devcontainers/openbao-agent:1": {
      "configPath": "/workspace-config/openbao-agent.hcl"
    }
  }
}
```

See the [OpenBao Agent documentation](https://openbao.org/docs/agent-and-proxy/agent/) for configuration syntax and supported auto-auth methods.

## Options

| Option        | Type   | Default                  | Description                                                       |
| ------------- | ------ | ------------------------ | ----------------------------------------------------------------- |
| `version`     | string | `latest`                 | OpenBao release version, with or without the upstream `v` prefix. |
| `serviceUser` | string | `automatic`              | User account that runs OpenBao Agent.                             |
| `configPath`  | string | `/etc/openbao/agent.hcl` | Absolute path to the user-supplied Agent configuration file.      |

For `latest`, the installer selects the newest stable release containing a Linux archive for the current architecture. Archives come from the official `openbao/openbao` GitHub releases and are verified against the published `checksums.txt` file.

## Service operation

The s6 supervisor remains root-controlled. A user with sudo access can restart the Agent after changing its configuration:

```sh
sudo /command/s6-svc -r /run/service/openbao-agent
```

The installed command is `bao`. The Feature does not create a `vault` alias because an existing HashiCorp Vault installation may own that command.
