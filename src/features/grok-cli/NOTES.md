Runs xAI's native installer as the resolved Dev Container user and symlinks its user-owned executable into `/usr/local/bin/grok`.

The native installer creates optional user-local aliases. The Feature retains its `grok` alias but removes its `agent` alias, or restores a pre-existing `agent` entry, so other coding-agent Features remain composable.

Example usage:

```json
{
  "features": {
    "ghcr.io/wyrd-company/devcontainers/grok-cli:1": {}
  }
}
```

## Trademarks

This feature is not affiliated with or endorsed by SpaceXSI. Grok and its logo are trademarks of SpaceXSI. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the Grok logomark from the [xAI brand guidelines](https://x.ai/legal/brand-guidelines) (`Grok_Logomark_Dark.svg`). The guidelines allow its unaltered use to refer accurately to xAI's services, without implied endorsement.
