---
title: Overview
product: base
order: 1
---

`ghcr.io/wyrd-company/devcontainers/base` derives from Microsoft's Ubuntu Dev Container base and adds [s6-overlay](https://github.com/just-containers/s6-overlay) as PID 1.

## Supported variants

| Ubuntu release | Codename   | Architectures    |
| -------------- | ---------- | ---------------- |
| 24.04 LTS      | `noble`    | `amd64`, `arm64` |
| 26.04 LTS      | `resolute` | `amd64`, `arm64` |

## Tags

Published rolling tags are explicit and never silently change Ubuntu releases:

- `ghcr.io/wyrd-company/devcontainers/base:noble`
- `ghcr.io/wyrd-company/devcontainers/base:ubuntu24.04`
- `ghcr.io/wyrd-company/devcontainers/base:resolute`
- `ghcr.io/wyrd-company/devcontainers/base:ubuntu26.04`

Each build also receives a dated immutable tag, for example `20261019.69-noble`, for rollback. Twelve dated builds are kept for each variant.

The image is rebuilt weekly and when its sources change. It is published with provenance and Software Bill of Materials attestations.

## Upstream

The image preserves the tools, non-root `vscode` user, and Dev Container metadata supplied by [`mcr.microsoft.com/devcontainers/base`](https://github.com/devcontainers/images/tree/main/src/base-ubuntu). Microsoft and other upstream components retain their respective copyright and license notices.
