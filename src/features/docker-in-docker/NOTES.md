## Runtime requirement

This Feature registers preparation, [containerd](https://containerd.io/), and `dockerd` as native [s6-overlay](https://github.com/just-containers/s6-overlay) 3 services. The image must provide `/init` as its entrypoint, and `devcontainer.json` must set `"overrideCommand": false`.

[Docker](https://www.docker.com/) CE is installed by default. Set `"moby": true` to request Microsoft-packaged [Moby](https://mobyproject.org/) explicitly. The installation fails rather than substituting Docker CE when the complete requested Moby package set is unavailable. Moby is unavailable on Ubuntu Resolute and Debian Trixie.

This Feature derives from Microsoft's [Dev Container Docker-in-Docker Feature](https://github.com/devcontainers/features/tree/main/src/docker-in-docker) under the MIT License. It replaces the upstream entrypoint hook with native s6 supervision.

## Limitations

This docker-in-docker Dev Container Feature is roughly based on the [official docker-in-docker wrapper script](https://github.com/moby/moby/blob/master/hack/dind) that is part of the [Moby project](https://mobyproject.org/). With this in mind:

- As the name implies, the Feature is expected to work when the host is running Docker (or the OSS Moby container engine it is built on). It may be possible to get running in other container engines, but it has not been tested with them.
- The host and the container must be running on the same chip architecture. You will not be able to use it with an emulated x86 image with Docker Desktop on an Apple Silicon Mac, like in this example:
  ```
  FROM --platform=linux/amd64 mcr.microsoft.com/devcontainers/typescript-node:24
  ```
  See [Issue #219](https://github.com/devcontainers/features/issues/219) for more details.

## OS Support

This Feature should work on recent versions of Debian/Ubuntu-based distributions with the `apt` package manager installed.

Ubuntu Resolute selects `iptables-nft` at runtime because its kernel does not provide the legacy iptables NAT tables.

`bash` is required to execute the `install.sh` script.

## Persisted state

This Feature mounts two named Docker volumes into the dev container so that the daemons have writable, non-overlay storage for their state:

- `dind-var-lib-docker-${devcontainerId}` → `/var/lib/docker`
- `dind-var-lib-containerd-${devcontainerId}` → `/var/lib/containerd`

The `/var/lib/containerd` mount is required when the dev container's root filesystem is itself an overlayfs mount (the default in Kubernetes / containerd-backed hosts, GitHub Codespaces, and Docker with the containerd image store enabled). Without it, the standalone `containerd` started by this Feature would place its overlayfs snapshotter data on an overlay rootfs, causing overlay-on-overlay mounts to fail with `invalid argument`. See [issue #1639](https://github.com/devcontainers/features/issues/1639) for background.

Because both volumes are scoped to `${devcontainerId}`, each dev container gets its own state and rebuilds preserve images and snapshots. Removing the dev container does not automatically remove these volumes; clean them up with `docker volume rm` if you want to reclaim space.

When the [Ansible](https://www.ansible.com/) Feature is installed, Docker starts only after the `ansible-setup` s6-rc oneshot finishes, and does not start if it fails. Without Ansible, startup does not change. The preparation oneshot waits, so [containerd](https://containerd.io/) and `dockerd` also wait.

## Trademarks

This feature is not affiliated with or endorsed by Docker, Inc. Docker and its logo are trademarks of Docker, Inc. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the Docker mark from the [Docker media resources](https://www.docker.com/company/newsroom/media-resources/) (`docker-mark-ocean-blue.svg`).
