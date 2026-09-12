# Codex CLI

Installs the OpenAI Codex CLI from npm for the resolved Dev Container user. Node.js 24 LTS is supplied through the official Dev Container Node Feature.

The package, executable, and Codex state remain owned by the user rather than root.

## Options

| Option    | Type   | Default  | Description                            |
| --------- | ------ | -------- | -------------------------------------- |
| `version` | string | `latest` | Codex CLI version to install from npm. |

## Example usage

```json
{
  "features": {
    "ghcr.io/wyrd-company/devcontainers/codex-cli:1": {}
  }
}
```

## Programmatic Codex sessions

`async-codex-mcp` uses `codex app-server` and supports Codex `0.153.4` and `0.154.0`. The older `codex mcp-server` interface is absent in `0.154.0`. Use `async-codex-mcp` `0.6.0` or later with that CLI.

For a reproducible tools workspace, set this Feature's `version` option to `0.154.0`. The Feature default remains `latest`; its tests generate the app-server schema to verify that the programmatic interface is available. The async wrapper also checks the app-server initialization handshake and reports a named startup failure if the interface is unavailable.
