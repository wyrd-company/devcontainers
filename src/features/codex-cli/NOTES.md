Installs the npm-distributed Codex CLI in the selected user's `~/.local` directory and runs a shared app-server under s6-overlay 3 by default.

`serviceUser` defaults to the remote user, container user, `vscode`, then `root`. `startAppServer=false` installs only the CLI. `remoteControl=true` adds remote control to the shared server and requires ChatGPT sign-in with `codex login`.

The TUI and `async-codex-mcp` use the private control socket under the same `CODEX_HOME` (default `~/.codex`). Set custom profile paths in `containerEnv`. Mount that native state directory to retain sign-in and history across rebuilds; this Feature declares no mounts.
