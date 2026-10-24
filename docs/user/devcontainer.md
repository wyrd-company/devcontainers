---
title: Use the image
product: base
order: 2
install: true
---

Name the image in `devcontainer.json`. Set `"overrideCommand": false` so that the image command stays active and s6-overlay keeps running as PID 1.

```json
{
  "image": "ghcr.io/wyrd-company/devcontainers/base:noble",
  "overrideCommand": false
}
```

Use `resolute` or `ubuntu26.04` for Ubuntu 26.04 LTS.

## Features

The service Features in [wyrd-company/devcontainers](https://github.com/wyrd-company/devcontainers) require this image, or another image that uses s6-overlay 3 with `/init` as its entrypoint. Add them in `features`:

```json
{
  "image": "ghcr.io/wyrd-company/devcontainers/base:noble",
  "overrideCommand": false,
  "features": {
    "ghcr.io/wyrd-company/devcontainers/caddy:1": {}
  }
}
```

Do not add the `common-utils` Feature on top of this image; it may reinstate unrestricted sudo for the user it manages. See [sudo](sudo.md).
