Runs Cursor's native installer as the resolved Dev Container user and symlinks its user-owned `agent` and `cursor-agent` executables into `/usr/local/bin`.

Cursor selects the installed CLI version and manages updates in place.

Example usage:

```json
{
  "features": {
    "ghcr.io/wyrd-company/devcontainers/cursor-agent-cli:1": {}
  }
}
```

Logo: the Cursor cube from the [Cursor brand assets](https://cursor.com/brand) (`CUBE_2D_LIGHT.svg`). Cursor publishes the assets to represent Cursor accurately and states no other terms. Used here only to identify the upstream project.
