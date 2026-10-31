# Changelog

## 2.2.0

### Features

- When the Ansible Feature is installed, the services of this Feature start after its `ansible-setup` oneshot succeeds. Without Ansible, startup does not change. The Feature adds the Ansible Feature to `installsAfter`.

## 2.1.0

### Features

- The service runs the native update launcher of T3 Code. Connected clients can update the server in place without sudo. A failed update restores the database and the previous server.
- `t3code-server-update` can queue a runtime for the next start (`--no-restart`) and force a fresh install (`--force`). It leaves a stopped service stopped.
- `t3code-server-update --status` shows the active, queued and installed versions.

## 2.0.0

### Breaking changes

- The option `packageSource` is removed. The feature installs only upstream T3 Code. Fork sources, npm specs and tarball URLs no longer work. Set `version` instead.
- An exact `version` or `latest` now installs the upstream release archive. Any other `version` is an npm range or dist-tag.
- The feature installs each version in `<home>/.t3/runtime/versions/<version>`. To keep the state when you rebuild, mount the whole `<home>/.t3` directory.

### Features

- The command `t3code-server-update` installs a version, selects it and restarts the service. The service user can run it with `sudo`. It accepts only `latest` or an exact version.

## 1.2.1

### Fixes

- The service runs the platform binary of T3 Code. Before, it ran the Node shim, which does not pass signals on. A restart left the old server running on the port, and the new server failed to start.

## 1.2.0

### Features

- A `packageSource` that points to a GitHub repository installs the release asset of a fork. With `version` set to `latest`, the feature selects the newest stable fork server release.

## 1.1.0

### Features

- Option `packageSource` selects an npm package spec or a tarball URL to install in place of `t3@<version>`.

## 1.0.0

### Features

- Installs the T3 Code CLI and runs `t3 serve` as an s6-overlay service for the selected user.
- Options `port`, `host` and `serveMode` set how the server starts. Option `serviceUser` selects the user.
- Option `dnsName` shows T3 Code over HTTPS through the Caddy feature.
