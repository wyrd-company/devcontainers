Installs the npm-distributed Codex CLI in the selected user's `~/.local` directory and runs a shared app-server under s6-overlay 3 by default.

`serviceUser` defaults to the remote user, container user, `vscode`, then `root`. Set both `startAppServer=false` and `execServer="false"` for CLI-only installation. `remoteControl=true` adds remote control to the shared server and requires ChatGPT sign-in with `codex login`.

The TUI and `async-codex-mcp` use the private control socket under the same `CODEX_HOME` (default `~/.codex`). Set custom profile paths in `containerEnv`. Mount that native state directory to retain sign-in and history across rebuilds; this Feature declares no mounts.

`execServer` is a string: `"false"` disables the optional S6 service, `"true"` enables it without authentication, and other values supply quoted CLI flags. Secret files can be mounted at runtime. The installer does not read them; Codex validates and loads them when the service starts.

`dnsName` integrates with Caddy. App-server uses `/`, retaining the shared private Unix socket through a same-user S6 socket bridge. Exec-server uses `/exec-server`. Listeners bind to IPv4 loopback; `appServerPort` defaults to 4500 and `execServerPort` to 4501. The Caddy and DNS readiness directories are required.

The app-server Caddy route permits unauthenticated command execution. Exec-server authentication protects only its own route. The installer warns about each unauthenticated enabled route. Restrict access through Caddy or the network; `dnsName` does not authenticate clients.
