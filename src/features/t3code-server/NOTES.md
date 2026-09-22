T3 Code runs under s6-overlay with `${HOME}/.t3` as its base directory. `sudo t3code-server-update [version]` updates it from inside the container; `t3code-server-update --status` shows the selected and installed versions.

Mint a pairing code manually under the service user's home context:

```bash
sudo -u vscode t3 auth pairing create --base-dir /home/vscode/.t3
```

Codex is intentionally not installed by this Feature. Add `ghcr.io/wyrd-company/devcontainers/codex-cli:1` separately when needed.
