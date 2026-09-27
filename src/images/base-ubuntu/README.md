# Ubuntu Dev Container base with s6-overlay

This image derives from Microsoft's Ubuntu Dev Container base and adds [s6-overlay](https://github.com/just-containers/s6-overlay) as PID 1.

## Supported variants

| Ubuntu release | Codename   | Architectures    |
| -------------- | ---------- | ---------------- |
| 24.04 LTS      | `noble`    | `amd64`, `arm64` |
| 26.04 LTS      | `resolute` | `amd64`, `arm64` |

Published rolling tags are explicit and never silently change Ubuntu releases:

- `ghcr.io/wyrd-company/devcontainers/base:noble`
- `ghcr.io/wyrd-company/devcontainers/base:ubuntu24.04`
- `ghcr.io/wyrd-company/devcontainers/base:resolute`
- `ghcr.io/wyrd-company/devcontainers/base:ubuntu26.04`

Each build also receives a dated immutable tag for rollback.

## Services

Add native s6-rc service definitions under `/etc/s6-overlay/s6-rc.d` and include services in `/etc/s6-overlay/user-bundles.d/user/contents.d`. Services should depend on the `base` bundle unless they intentionally need to start earlier.

## sudo

The `vscode` user has passwordless `sudo` for two purposes only:

- Package installation: `apt-get update`, `apt-get install`, and the `apt` equivalents. `DEBIAN_FRONTEND` is passed through. The operation must be the first word that is not an option. Options that take a value use the `-o value`, `-ovalue`, or `--name=value` form. Package names must not end in `-` or `_`, which apt treats as remove and purge.
- s6-overlay service control: `s6-svc` and `s6-svstat` on `/run/service/*`, and `s6-rc`.

```bash
sudo apt-get update && sudo apt-get install -y --no-install-recommends jq
sudo /command/s6-svc -r /run/service/dagu
```

Every other command is denied. Image builds and Dev Container Features still run as root, so they are unaffected. Do not add the `common-utils` Feature on top of this image; it may reinstate unrestricted sudo for the user it manages.

The policy lives in `/etc/sudoers.d/vscode`. `apt-get install` accepts local `.deb` files and `-o` options, so this is a guardrail against casual privilege use rather than a hard security boundary.

## Upstream

The image preserves the tools, non-root `vscode` user, and Dev Container metadata supplied by [`mcr.microsoft.com/devcontainers/base`](https://github.com/devcontainers/images/tree/main/src/base-ubuntu). Microsoft and other upstream components retain their respective copyright and license notices.
