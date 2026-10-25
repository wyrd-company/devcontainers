# Changelog

## 2.0.0

### Breaking changes

- OpenBao Agent now runs as `root` by default. Before, it ran as the remote user. The Agent keeps its first credential and its token out of the reach of the remote user. To keep the old behavior, set `serviceUser` to `automatic`. Make sure that the selected user can read the authentication inputs and write the template destinations and token sinks.

### Features

- Other features can load secrets that the Agent renders to `/run/openbao/secrets/<feature-id>.env`. Add a `template` with that destination to the Agent configuration.
- The group `openbao-secrets` gives the consuming services read access to the rendered files.
- The command `openbao-wait-for-secrets` blocks until a feature's secret file is readable.
- The `opentelemetry-collector` and `dagu` features load their secret files.

### Fixes

- The Agent refuses to clear the render directory when it is a mount point, a symbolic link or a nested mount.
- The scan of the Agent configuration ignores comments, here-documents and strings, and handles CRLF line endings. It matches only exact `destination` values.

## 1.0.0

### Features

- Installs the official OpenBao `bao` binary and runs `bao agent` as an s6-overlay service.
- The installer checks the download against the published checksums. It supports `amd64` and `arm64`.
- You provide the Agent configuration at `/etc/openbao/agent.hcl`. Option `configPath` selects another path.
- Option `serviceUser` selects the user that runs the Agent.
