# OpenBao Agent

Installs the official OpenBao `bao` binary and runs `bao agent` as an s6-overlay longrun service. The Feature requires a Debian/Ubuntu image with s6-overlay 3 and supports `amd64` and `arm64`.

OpenBao Agent runs as `root` by default, unlike the other service Features. The Agent holds the first credential and the token that every rendered secret derives from; running as `root` keeps both out of the remote user's reach, so a process running as that user, such as a coding agent, cannot read them. Rendered secret files reach other Features through the `openbao-secrets` group. Set `serviceUser` to override: `automatic` prefers the remote user, container user, `vscode`, then `root`, and a user name selects that user. Authentication inputs must be readable, and template destinations and token sinks writable, by the selected user.

## Configuration

The Feature does not create an Agent configuration or choose an authentication method. Supply the configuration as a read-only mount at `/etc/openbao/agent.hcl`:

```json
{
  "image": "ghcr.io/wyrd-company/devcontainers/base:noble",
  "overrideCommand": false,
  "features": {
    "ghcr.io/wyrd-company/devcontainers/openbao-agent:2": {}
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
    "ghcr.io/wyrd-company/devcontainers/openbao-agent:2": {
      "configPath": "/workspace-config/openbao-agent.hcl"
    }
  }
}
```

See the [OpenBao Agent documentation](https://openbao.org/docs/agent-and-proxy/agent/) for configuration syntax and supported auto-auth methods.

## Secret files for other Features

A Feature that runs a service loads `/run/openbao/secrets/<feature-id>.env` before it starts the service. The Agent configuration decides which files exist: add one `template` whose `destination` is that path.

```hcl
template {
  destination = "/run/openbao/secrets/opentelemetry-collector.env"
  perms       = "0640"
  contents    = <<-EOT
    {{ with secret "secret/data/sample-application" -}}
    SAMPLE_API_TOKEN={{ .Data.data.token }}
    {{- end }}
  EOT
}
```

Each line is `NAME=value`. The value is literal text to the end of the line and is not shell syntax. Lines that start with `#` are comments. A variable that the container environment already sets keeps its container value.

| Item                                    | Purpose                                                                                                  |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `/run/openbao/secrets`                  | Render directory. Owner `serviceUser`, group `openbao-secrets`, mode `2750`. Emptied at container start. |
| `openbao-secrets` group                 | Read access to rendered files. Features that load a secret file add their service user to this group.    |
| `openbao-wait-for-secrets <feature-id>` | Blocks until the file for that Feature is readable. Returns at once when no template names the file.     |
| `openbao-secrets` s6 oneshot            | Creates the render directory before the Agent and the consuming services start.                          |

`openbao-wait-for-secrets` reads the Agent configuration at `configPath` and ignores lines that start with `#` or `//`. The consuming service user must be able to read the configuration; when it cannot, the helper logs the condition and does not wait. The wait has no time limit, so a service whose secret cannot be rendered stays down and the helper logs one line each second.

A service reads its secret file once, at start. Restart the service after a secret changes:

```sh
sudo /command/s6-svc -r /run/service/opentelemetry-collector
```

The `opentelemetry-collector` and `dagu` Features load secret files.

## Options

| Option        | Type   | Default                  | Description                                                       |
| ------------- | ------ | ------------------------ | ----------------------------------------------------------------- |
| `version`     | string | `latest`                 | OpenBao release version, with or without the upstream `v` prefix. |
| `serviceUser` | string | `root`                   | User account that runs OpenBao Agent; see above for the override. |
| `configPath`  | string | `/etc/openbao/agent.hcl` | Absolute path to the user-supplied Agent configuration file.      |

For `latest`, the installer selects the newest stable release containing a Linux archive for the current architecture. Archives come from the official `openbao/openbao` GitHub releases and are verified against the published `checksums.txt` file.

## Service operation

The s6 supervisor remains root-controlled. A user with sudo access can restart the Agent after changing its configuration:

```sh
sudo /command/s6-svc -r /run/service/openbao-agent
```

The installed command is `bao`. The Feature does not create a `vault` alias because an existing HashiCorp Vault installation may own that command.
