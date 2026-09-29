# Codex CLI

Installs the OpenAI Codex CLI from npm in the selected user's `~/.local` directory. Node.js 24 LTS comes from the official Node Feature. S6-overlay runs a shared app-server with the user's environment, `HOME`, and `USER`.

## Options

| Option           | Type    | Default     | Description                                                                                                             |
| ---------------- | ------- | ----------- | ----------------------------------------------------------------------------------------------------------------------- |
| `version`        | string  | `latest`    | Codex CLI version from npm.                                                                                             |
| `startAppServer` | boolean | `true`      | Run the app-server under s6-overlay 3. Set false for CLI-only installation.                                             |
| `remoteControl`  | boolean | `false`     | Enable remote control on the same app-server. Requires `startAppServer` and ChatGPT sign-in with `codex login`.         |
| `serviceUser`    | string  | `automatic` | CLI owner and service user. Select the remote user, container user, `vscode`, then `root`, or specify an existing user. |

## Example usage

```json
{
  "image": "ghcr.io/wyrd-company/devcontainers/base:noble",
  "features": {
    "ghcr.io/wyrd-company/devcontainers/codex-cli:2": {
      "remoteControl": true
    }
  }
}
```

The service requires an s6-overlay 3 image and a Codex CLI with `app-server --listen unix://` support. Remote control also requires `app-server --remote-control` support. The launcher uses the installed CLI directly, so user-owned npm updates apply when S6 next starts the service. CLI-only installations can use older versions and other base images.

## Shared app-server

The service runs `codex app-server --listen unix://`, adding `--remote-control` when enabled. It uses Codex's internal daemon startup marker to disable restoration of saved remote-control preferences when the option is false. It does not change saved settings. Codex owns its private control socket beneath `$CODEX_HOME/app-server-control/app-server-control.sock`; `CODEX_HOME` defaults to `~/.codex`. The TUI and `async-codex-mcp` discover this socket under the same user profile. Remote clients attach to that same server when remote control is enabled. Plain `codex remote-control` creates a separate foreground server with a temporary socket.

Use `codex remote-control pair` to obtain a pairing code after sign-in. Manage the process through S6: `/command/s6-svc -r /run/service/codex-cli` restarts it when run by an authorized operator. The Feature adds no sudo grants. A service restart interrupts its clients.

All clients share the server's startup environment. Set `CODEX_HOME` in `containerEnv` so that the service and clients use the same profile. Secrets and state remain in Codex's native directory; the Feature adds no mounts. To retain sign-in and thread history across rebuilds, mount the selected user's `.codex` directory or the custom `CODEX_HOME` directory.
