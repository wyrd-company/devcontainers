# Codex CLI

Installs the OpenAI [Codex](https://github.com/openai/codex) CLI from [npm](https://www.npmjs.com/) in the selected user's `~/.local` directory. [Node.js](https://nodejs.org/) 24 LTS comes from the official [Dev Container Node Feature](https://github.com/devcontainers/features/tree/main/src/node). [s6-overlay](https://github.com/just-containers/s6-overlay) runs a shared app-server with the user's environment, `HOME`, and `USER`.

## Options

| Option           | Type    | Default     | Description                                                                                                                             |
| ---------------- | ------- | ----------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `version`        | string  | `latest`    | Codex CLI version from npm.                                                                                                             |
| `startAppServer` | boolean | `true`      | Run the shared app-server under S6.                                                                                                     |
| `remoteControl`  | boolean | `false`     | Enable remote control on the shared app-server. Requires `startAppServer` and [ChatGPT](https://chatgpt.com/) sign-in.                  |
| `execServer`     | string  | `false`     | `false` disables exec-server; `true` enables it without authentication; any other value supplies additional CLI arguments.              |
| `execServerPort` | string  | `4501`      | Exec-server IPv4 loopback port.                                                                                                         |
| `dnsName`        | string  | empty       | Fully qualified DNS name served by the [Caddy](https://caddyserver.com/) Feature. App-server uses `/`; exec-server uses `/exec-server`. |
| `appServerPort`  | string  | `4500`      | IPv4 loopback port for the app-server socket bridge when `dnsName` is set.                                                              |
| `serviceUser`    | string  | `automatic` | CLI and service owner: remote user, container user, `vscode`, then `root`, or an explicit existing user.                                |

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

The service requires an s6-overlay 3 image and a Codex CLI with `app-server --listen unix://` support. Remote control also requires `app-server --remote-control` support. The launcher uses the installed CLI directly, so user-owned npm updates apply when S6 next starts the service. Set both `startAppServer=false` and `execServer="false"` for CLI-only installation. CLI-only installations can use older versions and other base images.

## Shared app-server

The service runs `codex app-server --listen unix://`, adding `--remote-control` when enabled. It uses Codex's internal daemon startup marker to disable restoration of saved remote-control preferences when the option is false. It does not change saved settings. Codex owns its private control socket beneath `$CODEX_HOME/app-server-control/app-server-control.sock`; `CODEX_HOME` defaults to `~/.codex`. The TUI and [`async-codex-mcp`](https://github.com/wyrd-company/async-codex-mcp) discover this socket under the same user profile. Remote clients attach to that same server when remote control is enabled. Plain `codex remote-control` creates a separate foreground server with a temporary socket.

Use `codex remote-control pair` to obtain a pairing code after sign-in. Manage the process through S6: `/command/s6-svc -r /run/service/codex-cli` restarts it when run by an authorized operator. The Feature adds no sudo grants. A service restart interrupts its clients.

All clients share the server's startup environment. Set `CODEX_HOME` in `containerEnv` so that the service and clients use the same profile. Secrets and state remain in Codex's native directory; the Feature adds no mounts. To retain sign-in and thread history across rebuilds, mount the selected user's `.codex` directory or the custom `CODEX_HOME` directory.

## Exec-server

The optional S6 service runs `codex exec-server --listen ws://127.0.0.1:<execServerPort>` as the selected user. It uses Codex's exec-specific protocol, separately from the app-server thread/turn API. It can run with `startAppServer=false`.

Use string values for `execServer`. `"false"` or an empty value disables it; `"true"` starts it without authentication. Other values are parsed as quoted CLI arguments. Use single quotes around arguments with spaces: the [devcontainers CLI](https://github.com/devcontainers/cli) writes option values inside double-quoted shell assignments. Arguments are appended after the Feature's listener argument. Codex validates flag combinations at startup. Shell commands, operators, glob expansion, and environment substitution are not supported. Supply literal arguments; the installer parser does not expand environment variables. Use absolute paths for secret files, including runtime mounts; the installer does not read those files.

Capability-token example:

```json
"execServer": "--ws-auth capability-token --ws-token-file /run/secrets/exec-token"
```

Signed bearer example with optional issuer and audience:

```json
"execServer": "--ws-auth signed-bearer-token --ws-shared-secret-file '/run/secrets/exec key' --ws-issuer sample --ws-audience sample-client"
```

Codex also accepts `--ws-token-sha256` and `--ws-max-clock-skew-seconds`. Authentication is checked when the WebSocket connects. Manage the exec-server with `/command/s6-svc -r /run/service/codex-exec-server` as an authorized operator. The Feature does not create secret files or add secret mounts.

## Caddy

Set `dnsName` and include the Caddy Feature. Its configuration and DNS readiness directories must be present. Both services use one hostname:

- `wss://<dnsName>/` connects to the shared app-server when `startAppServer=true`.
- `wss://<dnsName>/exec-server` connects to exec-server when `execServer` is enabled.

A disabled service's route returns HTTP 404. App-server retains its private Unix socket for the TUI and MCP. An S6-managed [`socat`](http://www.dest-unreach.org/socat/) bridge runs as the same service user and exposes that socket on `127.0.0.1:<appServerPort>` for Caddy. The bridge follows runtime `CODEX_HOME`, including symlinked profiles. Socket permissions and the Caddy service user are unchanged. App-server requests with browser `Origin` headers are rejected, matching Codex's native TCP listener. The two enabled listeners must use different ports.

**Warning:** The app-server Caddy route is unauthenticated and permits command execution. Exec-server authentication does not protect the app-server route. If exec-server is enabled without authentication, its Caddy route also permits unauthenticated command execution. The installer logs these warnings, including the app-server warning when exec-server remains `"false"`. Restrict access through Caddy or the network. `dnsName` alone does not authenticate clients.

Example with both routes:

```json
{
  "image": "ghcr.io/wyrd-company/devcontainers/base:noble",
  "features": {
    "ghcr.io/wyrd-company/devcontainers/caddy:1": {},
    "ghcr.io/wyrd-company/devcontainers/codex-cli:2": {
      "dnsName": "sample-codex.example.test",
      "execServer": "--ws-auth capability-token --ws-token-file /run/secrets/exec-token"
    }
  }
}
```

## Ansible

When the [Ansible](https://www.ansible.com/) Feature is installed, the Codex services starts only after the `ansible-setup` s6-rc oneshot finishes. If the oneshot fails, the Codex services does not start. This Feature declares `installsAfter` for the Ansible Feature, so that the `ansible-setup` service definition exists when this installer runs. The installer adds the dependency only when that definition exists. Without Ansible, startup does not change. This covers the app-server and the exec-server when each is enabled. The app-server proxy starts after the app-server, so it also waits.

## Trademarks

This feature is not affiliated with or endorsed by OpenAI OpCo, LLC. OpenAI Codex and its logo are trademarks of OpenAI OpCo, LLC. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the OpenAI Blossom from the [OpenAI brand page](https://openai.com/brand/) (`Blossom_Light.svg`), without the construction guides. OpenAI's brand guidelines allow its unaltered use where it relates to OpenAI services.
