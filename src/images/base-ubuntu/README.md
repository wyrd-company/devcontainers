# Ubuntu Dev Container base with s6-overlay

`ghcr.io/wyrd-company/devcontainers/base` derives from Microsoft's Ubuntu Dev Container base and adds [s6-overlay](https://github.com/just-containers/s6-overlay) as PID 1. It has Ubuntu 24.04 LTS (`noble`, `ubuntu24.04`) and 26.04 LTS (`resolute`, `ubuntu26.04`) variants for `amd64` and `arm64`.

The image docs are in [`docs/user/`](../../../docs/user/) and published on [wyrd.foo](https://wyrd.foo/tools/base):

- [Overview](../../../docs/user/overview.md): variants, tags and upstream.
- [Use the image](../../../docs/user/devcontainer.md): `devcontainer.json` and Features.
- [Services](../../../docs/user/services.md): s6-rc service definitions.
- [sudo](../../../docs/user/sudo.md): the `vscode` user's sudo policy.

## Trademarks

This image is not affiliated with or endorsed by Canonical Ltd. Ubuntu and its logo are trademarks of Canonical Ltd. All trademarks and copyrights belong to their holders. The logo is used only to identify the operating system that this image is based on.

Logo: the Ubuntu Circle of Friends from Canonical's design assets ([CoF_white.svg](https://assets.ubuntu.com/v1/82818827-CoF_white.svg)), in Ubuntu orange.
