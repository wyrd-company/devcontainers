T3 Code's native update launcher runs under s6-overlay as the service user with `${HOME}/.t3` as its base directory. Connected clients can update compatible servers without sudo. T3 records the active version in `runtime/service-state.json`; the CLI follows that state. Legacy runtimes use `runtime/selected-version` and run directly.

`sudo t3code-server-update [version]` updates the server and launcher locally. `--no-restart` queues a runtime for the next start; `--force` reinstalls it while stopped. `t3code-server-update --status` shows active, queued and installed versions. Pending native updates recover before local maintenance. Local updates and downgrades do not provide native database rollback.

The native launcher passes host, port, mode and base directory through environment variables because it does not forward server flags. Release archives contain a standalone binary. npm runtimes exec the platform binary directly so s6 stops both launcher and server without leaving a Node shim's child behind.

Mount the service user's whole `${HOME}/.t3` directory to preserve runtime and application state across rebuilds. No mount is declared automatically.

Mint a pairing code manually under the service user's home context:

```bash
sudo -u vscode t3 auth pairing create --base-dir /home/vscode/.t3
```

Codex is intentionally not installed by this Feature. Add `ghcr.io/wyrd-company/devcontainers/codex-cli:1` separately when needed.
