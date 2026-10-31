# Changelog

## 2.1.0

### Features

- When the Ansible Feature is installed, the services of this Feature start after its `ansible-setup` oneshot succeeds. Without Ansible, startup does not change. The Feature adds the Ansible Feature to `installsAfter`.

## 2.0.0

### Breaking changes

- The feature now starts a shared Codex app-server as an s6-overlay service by default. The feature needs an s6-overlay 3 image for this. To install only the CLI, set `startAppServer` to `false` and keep `execServer` at `"false"`.

### Features

- The shared app-server uses the service user's `CODEX_HOME`. The TUI and `async-codex-mcp` connect to the same server.
- Option `remoteControl` turns on remote control for the shared app-server.
- Option `execServer` runs an optional Codex exec-server as a second service. Option `execServerPort` sets its port.
- Option `serviceUser` selects the user that owns the CLI and both services.
- Options `dnsName` and `appServerPort` publish the app-server and the exec-server through the Caddy feature.

## 1.0.1

### Fixes

- The documentation lists the Codex versions that work with `async-codex-mcp` and how to pin one.

## 1.0.0

### Features

- Installs the OpenAI Codex CLI from npm for the Dev Container user.
- Installs Node.js 24 through the official Node feature.
- Adds `codex` to the PATH. The package and its state stay owned by the user, not root.
- Option `version` selects the version to install.
