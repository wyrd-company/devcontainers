# OpenCode CLI

Installs the OpenCode CLI for the resolved Dev Container user using OpenCode's native installer and ensures `opencode` is available on the container `PATH`.

The executable, updater, and OpenCode state remain owned by the user rather than root. The Feature does not require Homebrew.

## Options

| Option    | Type   | Default  | Description                                                                         |
| --------- | ------ | -------- | ----------------------------------------------------------------------------------- |
| `version` | string | `latest` | OpenCode CLI version to install. Use `latest` or a specific version like `1.18.25`. |

## Example usage

```json
{
  "features": {
    "ghcr.io/wyrd-company/devcontainers/opencode-cli:1": {}
  }
}
```

## Trademarks

This feature is not affiliated with or endorsed by Anomaly. OpenCode and its logo are trademarks of Anomaly. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the opencode mark from [opencode-logo-light-square.svg](https://github.com/anomalyco/opencode/blob/1743d1a24e2356b3f631d3d384f44cb9d8359add/packages/console/app/src/asset/brand/opencode-logo-light-square.svg) (MIT), also offered on the [opencode brand page](https://opencode.ai/brand). No trademark terms are published.
