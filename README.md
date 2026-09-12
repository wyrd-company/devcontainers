# Dev containers

Dev Container images, Templates, and Features published by Wyrd Company to GitHub Container Registry.

## Ubuntu image

`ghcr.io/wyrd-company/devcontainers/base` derives from Microsoft's Ubuntu Dev Container base and adds s6-overlay as PID 1.

Supported rolling tags:

- `noble` and `ubuntu24.04`
- `resolute` and `ubuntu26.04`

Both variants support `amd64` and `arm64`.

## T3 Code web client image

`ghcr.io/wyrd-company/t3code-web` contains the unmodified static web client. The [`wyrd-company/t3code`](https://github.com/wyrd-company/t3code) fork owns its build and publication. Versioned and `latest` tags support `amd64` and `arm64`.

## Ubuntu Template

Apply the Template using:

```text
ghcr.io/wyrd-company/devcontainers/ubuntu:1
```

It defaults to Ubuntu 24.04 LTS (`noble`) and can select Ubuntu 26.04 LTS (`resolute`).

## Features

- `ghcr.io/wyrd-company/devcontainers/codex-cli:1`
- `ghcr.io/wyrd-company/devcontainers/claude-code-cli:1`
- `ghcr.io/wyrd-company/devcontainers/cursor-agent-cli:1`
- `ghcr.io/wyrd-company/devcontainers/grok-cli:1`
- `ghcr.io/wyrd-company/devcontainers/opencode-cli:1`
- `ghcr.io/wyrd-company/devcontainers/opencodex:1`
- `ghcr.io/wyrd-company/devcontainers/t3code-server:1`
- `ghcr.io/wyrd-company/devcontainers/dagu:1`
- `ghcr.io/wyrd-company/devcontainers/openobserve:1`
- `ghcr.io/wyrd-company/devcontainers/go:1`
- `ghcr.io/wyrd-company/devcontainers/sshd:1`
- `ghcr.io/wyrd-company/devcontainers/docker-outside-of-docker:1`
- `ghcr.io/wyrd-company/devcontainers/docker-in-docker:1`

The service Features require the Ubuntu base image above, or another image that uses s6-overlay 3 with `/init` as its entrypoint. Set `"overrideCommand": false` in `devcontainer.json` so the image command remains active. Docker CE is the default for both Docker Features; Microsoft-packaged Moby is available only as an explicit opt-in where its complete package set exists.

## Source layout

```text
src/
├── features/
├── images/
└── templates/
```

Feature and Template releases use the official Dev Container publishing action. Ubuntu images are rebuilt weekly and on relevant changes, published with provenance and Software Bill of Materials attestations, and retained with twelve dated rollback builds per variant.
