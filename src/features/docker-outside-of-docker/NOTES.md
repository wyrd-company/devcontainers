## Runtime requirement

This Feature registers [Docker](https://www.docker.com/) socket access as an [s6-overlay](https://github.com/just-containers/s6-overlay) 3 longrun service. The image must provide `/init` as its entrypoint, and `devcontainer.json` must set `"overrideCommand": false`.

Docker CE is installed by default. Set `"moby": true` to request Microsoft-packaged [Moby](https://mobyproject.org/) explicitly. The installation fails rather than substituting Docker CE when the complete requested Moby package set is unavailable. Moby is unavailable on Ubuntu Resolute and Debian Trixie.

This Feature derives from Microsoft's [Dev Container Docker-outside-of-Docker Feature](https://github.com/devcontainers/features/tree/main/src/docker-outside-of-docker) under the MIT License. It replaces the upstream entrypoint hook with native s6 supervision.

## Limitations

- As the name implies, the Feature is expected to work when the host is running Docker (or the OSS Moby container engine it is built on). It may be possible to get running in other container engines, but it has not been tested with them.
- The host and the container must be running on the same chip architecture. You will not be able to use it with an emulated x86 image with Docker Desktop on an Apple Silicon Mac, for example.
- This approach does not currently enable bind mounting the workspace folder by default, and cannot support folders outside of the workspace folder. Consider whether the [Docker-in-Docker Feature](../docker-in-docker) would better meet your needs given it does not have this limitation.

## Supporting bind mounts from the workspace folder

A common question that comes up is how you can use `bind` mounts from the Docker CLI from within the a dev container using this Feature (e.g. via `-v`). If you cannot use the [Docker-in-Docker Feature](../docker-in-docker), the only way to work around this is to use the **host**'s folder paths instead of the container's paths. There are 2 ways to do this

### 1. Use the `${localWorkspaceFolder}` as environment variable in your code

1. Add the following to `devcontainer.json`:

```json
"remoteEnv": { "LOCAL_WORKSPACE_FOLDER": "${localWorkspaceFolder}" }
```

2. Usage with Docker commands

```bash
docker run -it --rm -v ${LOCAL_WORKSPACE_FOLDER}:/workspace debian bash
```

3. Usage with [Docker Compose](https://docs.docker.com/compose/)

```yaml
version: "3.9"

services:
  debian:
    image: debian
    volumes:
      - ${LOCAL_WORKSPACE_FOLDER:-./}:/workspace
```

- The defaults value `./` is added so that the `docker-compose.yaml` file can work when it is run outside of the container

### 2. Change the workspace to `${localWorkspaceFolder}`

- This is useful if we don't want to edit the `docker-compose.yaml` file

1. Add the following to `devcontainer.json`

```json
"workspaceFolder": "${localWorkspaceFolder}",
"workspaceMount": "source=${localWorkspaceFolder},target=${localWorkspaceFolder},type=bind"
```

2. Rebuild the container.
3. When the container first started with this settings, select the Workspace with the absolute path to the working directory inside the container
4. Docker commands with bind mount should work as they did outside of the devcontainer

> **Note:** There is no `${localWorkspaceFolder}` when using the **Clone Repository in Container Volume** command in the [VS Code](https://code.visualstudio.com/) [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) ([info](https://github.com/microsoft/vscode-remote-release/issues/6160#issuecomment-1014701007)).

## OS Support

This Feature should work on recent versions of Debian/Ubuntu-based distributions with the `apt` package manager installed.

[`bash`](https://www.gnu.org/software/bash/) is required to execute the `install.sh` script.

When the [Ansible](https://www.ansible.com/) Feature is installed, the socket access service starts only after the `ansible-setup` s6-rc oneshot finishes, and does not start if it fails. Without Ansible, startup does not change.

## Trademarks

This feature is not affiliated with or endorsed by Docker, Inc. Docker and its logo are trademarks of Docker, Inc. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the Docker mark from the [Docker media resources](https://www.docker.com/company/newsroom/media-resources/) (`docker-mark-ocean-blue.svg`).
