# Dagu

Installs the official Dagu binary and runs `dagu start-all` as an s6-overlay longrun service. The Feature requires a Debian/Ubuntu image with s6-overlay 3 and supports `amd64` and `arm64`.

Dagu runs as the selected devcontainer user so that workflows receive that user's home directory, permissions, Git configuration, SSH credentials, development tools, and container environment. Automatic selection prefers the remote user, container user, `vscode`, then `root`.

The Feature uses Dagu's native per-user configuration and state paths. It does not create `config.yaml`, mount volumes, or change ownership beneath the service user's home directory. Configure bind mounts and their permissions in each `devcontainer.json` when configuration, DAG definitions, or run state must survive a rebuild.

## Caddy integration

Set `dnsName` when the Caddy Feature is present to expose Dagu through automatic HTTPS. The Feature registers the DNS name with Caddy's startup-readiness mechanism, writes a reverse-proxy fragment targeting Dagu on IPv4 loopback, and sets Dagu's public URL to `https://<dnsName>`.

```json
{
  "image": "ghcr.io/wyrd-company/devcontainers/base:noble",
  "overrideCommand": false,
  "features": {
    "ghcr.io/wyrd-company/devcontainers/caddy:1": {},
    "ghcr.io/wyrd-company/devcontainers/dagu:1": {
      "dnsName": "workflow.dev-environment.example.test"
    }
  }
}
```

Setting `dnsName` requires the Caddy Feature. Caddy-enabled configurations accept `127.0.0.1`, `localhost`, or `0.0.0.0` as the Dagu bind address. `localhost` is normalized to `127.0.0.1`, and Caddy always connects through IPv4 loopback.

## Secret file

The service loads `NAME=value` lines from `/run/openbao/secrets/dagu.env` into Dagu's environment when that file exists. Workflows read the values as environment variables. Values are literal text, and a variable that the container environment already sets keeps its container value.

When the OpenBao Agent Feature is present and its configuration has a `template` with that destination, Dagu does not start until the file is rendered:

```hcl
template {
  destination = "/run/openbao/secrets/dagu.env"
  perms       = "0640"
  contents    = <<-EOT
    {{ with secret "secret/data/workflows" -}}
    SAMPLE_API_TOKEN={{ .Data.data.token }}
    {{- end }}
  EOT
}
```

Dagu reads the file once, at start; restart the service after a secret changes. Without the OpenBao Agent Feature, any other source can supply the file, such as a bind mount.

## Options

| Option        | Type   | Default     | Description                                                       |
| ------------- | ------ | ----------- | ----------------------------------------------------------------- |
| `version`     | string | `latest`    | Dagu release version, with or without the upstream `v` prefix.    |
| `host`        | string | `127.0.0.1` | Interface used by Dagu. `localhost` is normalized to `127.0.0.1`. |
| `port`        | string | `8080`      | Port used by Dagu.                                                |
| `serviceUser` | string | `automatic` | User that runs Dagu and its workflows.                            |
| `dnsName`     | string | `""`        | Optional fully qualified DNS name exposed through Caddy.          |

The configured host and port are passed as command-line flags and therefore take precedence over Dagu's environment variables and `config.yaml`.

## Native Dagu locations

For a service user whose home is `/home/vscode`, Dagu defaults to:

| Purpose                  | Location                         |
| ------------------------ | -------------------------------- |
| Configuration and DAGs   | `/home/vscode/.config/dagu`      |
| Logs, history, and state | `/home/vscode/.local/share/dagu` |
| Service launcher         | `/usr/local/bin/dagu-service`    |
| s6 service               | `/etc/s6-overlay/s6-rc.d/dagu`   |

Dagu's built-in authentication presents its first-administrator setup flow when no user store exists.
