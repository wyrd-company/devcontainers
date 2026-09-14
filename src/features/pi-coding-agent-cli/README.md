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
