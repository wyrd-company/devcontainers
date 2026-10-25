# Changelog

## 2.0.0

### Breaking changes

- The feature now installs in `client` mode by default. In this mode no local proxy runs. Before, the feature always started a local proxy and dashboard. To keep that behavior, set `mode` to `standalone`.
- The options `port` and `dnsName` now apply only to `standalone` mode. Setting `dnsName` in `client` mode is an error.

### Features

- In `client` mode, a start-up step runs `ocx sync` when the container is connected to a Remote Hub and owns its saved connection. A failure or a disconnected client does not block container start.

## 1.0.0

### Features

- Installs OpenCodex (`ocx`) for the service user and runs `ocx start` as an s6-overlay service. The proxy and its dashboard listen on a loopback port.
- Option `dnsName` shows the dashboard over HTTPS through the Caddy feature.
- Options `version`, `port` and `serviceUser` select the version, the port and the user.
- `ocx update` works without root. Updates hold the proxy down while OpenCodex replaces the package. Concurrent or interrupted updates do not leave the proxy down.

### Fixes

- The installer checks the installed version against the version that npm resolves for the request. Dist-tags that start with a digit and versions with build metadata install correctly.
