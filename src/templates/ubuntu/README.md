# Ubuntu with s6-overlay

Creates an Ubuntu development container using Bob Langley's Microsoft-derived base image with s6-overlay as PID 1.

## Options

| Option         | Type   | Default | Description                            |
| -------------- | ------ | ------- | -------------------------------------- |
| `imageVariant` | string | `noble` | Ubuntu release: `noble` or `resolute`. |

## Usage

Apply the Template from:

```text
ghcr.io/wyrd-company/devcontainers/ubuntu:1
```

The generated `.devcontainer/devcontainer.json` references the corresponding explicit rolling image tag under `ghcr.io/wyrd-company/devcontainers/base`.

## Trademarks

This template is not affiliated with or endorsed by Microsoft Corporation or Canonical Ltd. Development Containers and its logo are trademarks of Microsoft Corporation. Ubuntu is a trademark of Canonical Ltd. All trademarks and copyrights belong to their holders. The logo is used only to identify the Development Containers specification that this template follows.

Logo: the Development Containers logo, a vector drawing of the official [devcontainers-logo.png](https://github.com/devcontainers/devcontainers.github.io/blob/12a1f11937c5cfe5f5b4c92250ebc91e528f897e/img/devcontainers-logo.png). The project publishes no vector logo.
