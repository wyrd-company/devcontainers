# Antigravity CLI

Installs the [Antigravity CLI](https://antigravity.google/product/cli) (`agy`) for the resolved Dev Container user using Google's native installer, and ensures `agy` is available on the container `PATH`.

The executable lives in the user's `~/.local/bin` and updates itself, so it stays upgradeable without a container rebuild. The Feature exposes only `agy` in `/usr/local/bin`, as a symlink.

The Feature does not edit shell profiles: the installer's own PATH and alias step is turned off.

## Options

This Feature has no options. Google's installer takes no version, and the CLI updates itself.

## State

The CLI keeps its sign-in, settings, MCP configuration and conversations in `~/.gemini` (`config/` for personal customizations such as `mcp_config.json`, `hooks.json` and `rules/`, and `antigravity-cli/` for its own state). The Feature declares no mount. To keep the sign-in across a rebuild, bind-mount `~/.gemini` from your workspace state, and keep that folder out of version control and backups: it holds the OAuth token.

## Example usage

```json
{
  "features": {
    "ghcr.io/wyrd-company/devcontainers/antigravity-cli:1": {}
  }
}
```

## Trademarks

This feature is not affiliated with or endorsed by Google LLC. Antigravity is a trademark of Google LLC. All trademarks and copyrights belong to their holders. This feature has no logo yet: Google publishes no standalone SVG of the Antigravity CLI mark, so the documentation site shows a monogram.
