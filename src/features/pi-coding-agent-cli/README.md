# Pi Coding Agent CLI

Installs the Pi coding agent from npm for the resolved Dev Container user. Node.js 24 LTS is supplied through the official Dev Container Node Feature.

The package, executable, and Pi state remain owned by the user rather than root.

## Options

| Option    | Type   | Default  | Description                               |
| --------- | ------ | -------- | ----------------------------------------- |
| `version` | string | `latest` | Pi coding agent version to install from npm. |

## Example usage

```json
{
  "features": {
    "ghcr.io/wyrd-company/devcontainers/pi-coding-agent-cli:1": {}
  }
}
```

## Trademarks

This feature is not affiliated with or endorsed by Mario Zechner. Pi and its logo are trademarks of Mario Zechner. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the pi mark from [pi.dev/favicon.svg](https://pi.dev/favicon.svg), in its light-theme color. The [pi repository](https://github.com/earendil-works/pi) is MIT and publishes no trademark terms.
