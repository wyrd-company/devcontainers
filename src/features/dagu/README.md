# Dagu

Installs the official [Dagu](https://dagu.sh/) binary and runs `dagu start-all` as an [s6-overlay](https://github.com/just-containers/s6-overlay) longrun service. The Feature requires a Debian/Ubuntu image with s6-overlay 3 and supports `amd64` and `arm64`.

Dagu runs as the selected devcontainer user so that workflows receive that user's home directory, permissions, Git configuration, SSH credentials, development tools, and container environment. Automatic selection prefers the remote user, container user, `vscode`, then `root`.

The Feature uses Dagu's native per-user configuration and state paths by default. Set `configPath` to a configuration file path to pass it to Dagu through `--config`. Use an absolute container path, such as `/etc/dagu/config.yaml`, and make the file readable by the service user before the service starts. An empty `configPath` keeps Dagu's native configuration lookup.

The Feature does not create `config.yaml`, mount volumes, or change ownership beneath the service user's home directory. Configure bind mounts and their permissions in each `devcontainer.json` when configuration, DAG definitions, or run state must survive a rebuild.

## Caddy integration

Set `dnsName` when the [Caddy](https://caddyserver.com/) Feature is present to expose Dagu through automatic HTTPS. The Feature registers the DNS name with Caddy's startup-readiness mechanism, writes a reverse-proxy fragment targeting Dagu on IPv4 loopback, and sets Dagu's public URL to `https://<dnsName>`.

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

When the [OpenBao Agent](https://openbao.org/) Feature is present and its configuration has a `template` with that destination, Dagu does not start until the file is rendered:

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
| `configPath`  | string | `""`        | Optional configuration file path passed as `--config`.            |
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

## Ansible

When the [Ansible](https://www.ansible.com/) Feature is installed, Dagu starts only after the `ansible-setup` s6-rc oneshot finishes. If the oneshot fails, Dagu does not start. This Feature declares `installsAfter` for the Ansible Feature, so that the `ansible-setup` service definition exists when this installer runs. The installer adds the dependency only when that definition exists. Without Ansible, startup does not change.

## Trademarks

This feature is not affiliated with or endorsed by Yota Hamada. Dagu and its logo are trademarks of Yota Hamada. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the Dagu mark from [dagu.sh/icon.svg](https://dagu.sh/icon.svg), without its white backdrop. No trademark terms are published.
