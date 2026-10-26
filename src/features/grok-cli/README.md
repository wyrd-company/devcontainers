# Grok CLI

Installs the Grok CLI for the resolved Dev Container user using xAI's native installer and ensures `grok` is available on the container `PATH`.

The executable, updater, and Grok state remain owned by the user rather than root.

The Feature does not retain xAI's optional `agent` alias, so it does not replace another tool that provides that command. It exposes only `grok` in `/usr/local/bin`.

## Options

| Option    | Type   | Default  | Description                                                                    |
| --------- | ------ | -------- | ------------------------------------------------------------------------------ |
| `version` | string | `latest` | Grok CLI version to install. Use `latest` or a specific version like `1.0.12`. |

## Example usage

```json
{
  "features": {
    "ghcr.io/wyrd-company/devcontainers/grok-cli:1": {}
  }
}
```

## Trademarks

This feature is not affiliated with or endorsed by SpaceXSI. Grok and its logo are trademarks of SpaceXSI. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the Grok logomark from the [xAI brand guidelines](https://x.ai/legal/brand-guidelines) (`Grok_Logomark_Dark.svg`).
