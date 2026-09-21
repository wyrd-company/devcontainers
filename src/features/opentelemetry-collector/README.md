# OpenTelemetry Collector

Installs an official OpenTelemetry Collector distribution and runs it as an s6-overlay longrun service. The Feature requires a Debian/Ubuntu image with s6-overlay 3 and supports `amd64` and `arm64`.

The Collector runs as the selected devcontainer user. Automatic selection prefers the remote user, container user, `vscode`, then `root`. The s6 supervisor remains root-controlled, so a user with sudo access can restart the Collector:

```sh
sudo /command/s6-svc -r /run/service/opentelemetry-collector
```

## Distributions

The `core` distribution is installed by default. Select `contrib` when the configuration needs components that are not included in core.

```json
{
  "image": "ghcr.io/wyrd-company/devcontainers/base:noble",
  "overrideCommand": false,
  "features": {
    "ghcr.io/wyrd-company/devcontainers/opentelemetry-collector:1": {
      "distribution": "contrib"
    }
  }
}
```

## Options

| Option         | Type   | Default     | Description                                               |
| -------------- | ------ | ----------- | --------------------------------------------------------- |
| `version`      | string | `latest`    | Release version, with or without the upstream `v` prefix. |
| `distribution` | string | `core`      | Official distribution to install: `core` or `contrib`.    |
| `serviceUser`  | string | `automatic` | User that runs the Collector.                             |

For `latest`, the installer selects the newest stable release that contains an archive for the selected distribution and architecture. Different distributions can resolve to different versions when an upstream release omits an artifact.

## Configuration

The Feature installs a starter configuration at `/etc/opentelemetry-collector/config.yaml`. It accepts traces, metrics, and logs over OTLP gRPC on `127.0.0.1:4317` and OTLP HTTP on `127.0.0.1:4318`, then writes received telemetry through the debug exporter. Its health endpoint listens on `127.0.0.1:13133`.

Replace the starter configuration with a read-only bind mount for project-specific pipelines:

```json
{
  "mounts": [
    "source=${localWorkspaceFolder}/.devcontainer/opentelemetry-collector.yaml,target=/etc/opentelemetry-collector/config.yaml,type=bind,readonly"
  ]
}
```

The Feature does not expose Collector endpoints outside the container. Bind them to another interface in the mounted configuration when access from the host or another container is required.

## Secret file

The service loads `NAME=value` lines from `/run/openbao/secrets/opentelemetry-collector.env` into the Collector environment when that file exists. Reference the values with the Collector's `${env:NAME}` syntax so that the configuration file holds no credential:

```yaml
exporters:
  otlphttp/central:
    endpoint: https://telemetry.example.test/api/default
    headers:
      Authorization: ${env:OTLP_AUTHORIZATION}
```

When the OpenBao Agent Feature is present and its configuration has a `template` with that destination, the Collector does not start until the file is rendered. The matching template builds the complete header value:

```hcl
template {
  destination = "/run/openbao/secrets/opentelemetry-collector.env"
  perms       = "0640"
  contents    = <<-EOT
    {{ with secret "secret/data/telemetry" -}}
    OTLP_AUTHORIZATION=Basic {{ printf "%s:%s" .Data.data.username .Data.data.token | base64Encode }}
    {{- end }}
  EOT
}
```

Values are literal text, so a value can contain spaces. A variable that the container environment already sets keeps its container value. The Collector reads the file once, at start; restart the service after a secret changes. Without the OpenBao Agent Feature, any other source can supply the file, such as a bind mount.

## Installed commands

The selected upstream command is installed as `otelcol` or `otelcol-contrib`. The stable `opentelemetry-collector` command points to the selected binary.

Release archives are downloaded from the official `open-telemetry/opentelemetry-collector-releases` repository and verified against the adjacent upstream SHA256 file.
