T3 Code runs under s6-overlay through its service launcher, with `${HOME}/.t3` as its base directory. The launcher applies updates requested by T3 Code clients; `sudo t3code-server-update [version]` updates it from inside the container.

Mint a pairing code manually under the service user's home context:

```bash
sudo -u vscode t3 auth pairing create --base-dir /home/vscode/.t3
```

Codex is intentionally not installed by this Feature. Add `ghcr.io/wyrd-company/devcontainers/codex-cli:1` separately when needed.
