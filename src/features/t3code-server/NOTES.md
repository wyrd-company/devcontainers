T3 Code runs under s6-overlay with `${HOME}/.t3` as its base directory. `sudo t3code-server-update [version]` updates it from inside the container; `t3code-server-update --status` shows the selected and installed versions.

Release archives carry the platform binary itself. When a version is installed through npm and its `t3` package ships platform binaries (`@t3code/t3-<platform>-<arch>`), the runtime execs that binary directly instead of the package's `t3` Node shim. The shim does not forward signals, so supervising it would orphan the server on restart and leave the port bound.

Mint a pairing code manually under the service user's home context:

```bash
sudo -u vscode t3 auth pairing create --base-dir /home/vscode/.t3
```

Codex is intentionally not installed by this Feature. Add `ghcr.io/wyrd-company/devcontainers/codex-cli:1` separately when needed.
