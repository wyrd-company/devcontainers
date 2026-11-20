Runs Google's native installer for the [Antigravity CLI](https://antigravity.google/product/cli) as the resolved Dev Container user and symlinks its user-owned `agy` executable into `/usr/local/bin`.

The installer takes no version. It installs the latest build, and the CLI updates itself in place.

The CLI keeps its sign-in, settings and conversations in `~/.gemini`. The Feature declares no mount; to keep them across a rebuild, bind-mount `~/.gemini` from your workspace state.

Example usage:

```json
{
  "features": {
    "ghcr.io/wyrd-company/devcontainers/antigravity-cli:1": {}
  }
}
```

## Trademarks

This feature is not affiliated with or endorsed by Google LLC. Antigravity is a trademark of Google LLC. All trademarks and copyrights belong to their holders. This feature has no logo yet: Google publishes no standalone SVG of the Antigravity CLI mark, so the documentation site shows a monogram.
