### **IMPORTANT NOTE**

- **Ids used to publish this Feature in the past - 'docker-from-docker'**

# Docker (docker-outside-of-docker) (docker-outside-of-docker)

Reuses the host [Docker](https://www.docker.com/) socket and supervises any required socket proxy with [s6-overlay](https://github.com/just-containers/s6-overlay).

## Example Usage

```json
"features": {
    "ghcr.io/wyrd-company/devcontainers/docker-outside-of-docker:1": {}
}
```

## Options

| Options Id                 | Description                                                                                                                                                                                                                                                                | Type    | Default Value             |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | ------------------------- |
| version                    | Select or enter a Docker/[Moby](https://mobyproject.org/) CLI version. (Availability can vary by OS version.)                                                                                                                                                              | string  | latest                    |
| moby                       | Install Microsoft-packaged Moby instead of Docker CE when the complete package set is available                                                                                                                                                                            | boolean | false                     |
| mobyBuildxVersion          | Install a specific version of moby-buildx when using Moby                                                                                                                                                                                                                  | string  | latest                    |
| dockerDashComposeVersion   | [Compose](https://docs.docker.com/compose/) version to use for docker-compose (v1 or v2 or none or latest)                                                                                                                                                                 | string  | latest                    |
| installDockerBuildx        | Install [Docker Buildx](https://github.com/docker/buildx)                                                                                                                                                                                                                  | boolean | true                      |
| installDockerComposeSwitch | Install [Compose Switch](https://github.com/docker/compose-switch) (provided docker compose is available) which is a replacement to the Compose V1 docker-compose (python) executable. It translates the command line into Compose V2 docker compose then runs the latter. | boolean | false                     |
| socketPath                 | Path where the Docker socket is mounted inside the container. For rootless Docker, override the mount in devcontainer.json to map your host socket to this path.                                                                                                           | string  | /var/run/docker-host.sock |

## Customizations

### [VS Code](https://code.visualstudio.com/) Extensions

- [`ms-azuretools.vscode-containers`](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-containers)

## Limitations

The image must use s6-overlay 3 with `/init` as its entrypoint. Set `"overrideCommand": false` in `devcontainer.json` so s6 remains PID 1. Docker CE is the default; `"moby": true` is an explicit opt-in and fails when the complete Moby package set is unavailable.

- As the name implies, the Feature is expected to work when the host is running Docker (or the OSS Moby container engine it is built on). It may be possible to get running in other container engines, but it has not been tested with them.
- The host and the container must be running on the same chip architecture. You will not be able to use it with an emulated x86 image with Docker Desktop on an Apple Silicon Mac, for example.
- This approach does not currently enable bind mounting the workspace folder by default, and cannot support folders outside of the workspace folder. Consider whether the [Docker-in-Docker Feature](../docker-in-docker) would better meet your needs given it does not have this limitation.

## Rootless Docker Support

By default, this feature expects the Docker socket at `/var/run/docker.sock` on the host, which works for standard (root) Docker installations. For **rootless Docker** setups where the socket is located at `/run/user/$UID/docker.sock` or `$XDG_RUNTIME_DIR/docker.sock`, you need to override the mount in your `devcontainer.json`:

```json
{
  "features": {
    "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {}
  },
  "mounts": [
    {
      "source": "/run/user/1000/docker.sock",
      "target": "/var/run/docker-host.sock",
      "type": "bind"
    }
  ]
}
```

**Notes:**

- Replace `1000` with your actual user ID (run `id -u` to find it)
- The feature will automatically detect the socket at `/var/run/docker-host.sock`
- Your custom mount will override the feature's default mount

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

3. Usage with Docker-compose

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

---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/devcontainers/features/blob/main/src/docker-outside-of-docker/devcontainer-feature.json). Add additional notes to a `NOTES.md`._

## Ansible

When the [Ansible](https://www.ansible.com/) Feature is installed, the socket access service starts only after the `ansible-setup` s6-rc oneshot finishes. If the oneshot fails, the socket access service does not start. This Feature declares `installsAfter` for the Ansible Feature, so that the `ansible-setup` service definition exists when this installer runs. The installer adds the dependency only when that definition exists. Without Ansible, startup does not change.

## Trademarks

This feature is not affiliated with or endorsed by Docker, Inc. Docker and its logo are trademarks of Docker, Inc. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the Docker mark from the [Docker media resources](https://www.docker.com/company/newsroom/media-resources/) (`docker-mark-ocean-blue.svg`).
