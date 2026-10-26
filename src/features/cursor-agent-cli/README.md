# Cursor Agent CLI

Installs the Cursor Agent CLI for the resolved Dev Container user using Cursor's recommended native installer and ensures `agent` and `cursor-agent` are available on the container `PATH`.

The installation, executable, updater, and Cursor state remain owned by the user rather than root. Cursor selects the installed CLI version and updates it in place because its installer does not expose a version argument.

## Example usage

```json
{
  "features": {
    "ghcr.io/wyrd-company/devcontainers/cursor-agent-cli:1": {}
  }
}
```

## Trademarks

This feature is not affiliated with or endorsed by Anysphere, Inc. Cursor and its logo are trademarks of Anysphere, Inc. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the Cursor cube from the [Cursor brand assets](https://cursor.com/brand) (`CUBE_2D_LIGHT.svg`).
