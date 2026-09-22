# T3 Code Server

Installs T3 Code as a pinned release runtime and runs `t3 serve` as the selected service user through a native s6-overlay 3 service. The service user updates it in place with `t3code-server-update`. Runtime state remains in the service user's home directory.

The Feature requires a Debian/Ubuntu image with s6-overlay 3 already installed. Release archives are self-contained; Node.js 24 is supplied through the official Dev Container Node Feature for npm package sources.

## Options

| Option          | Type   | Default     | Description                                                                                                                                                             |
| --------------- | ------ | ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `version`       | string | `latest`    | T3 Code version. With upstream, `latest` follows GitHub's latest upstream release. With a GitHub source, `latest` selects the greatest stable fork server tag by SemVer precedence. |
| `packageSource` | string | `""`        | Optional GitHub repository source, npm package spec, or tarball URL. Empty installs upstream T3 Code.                                                                   |
| `port`          | string | `3773`      | Port exposed by the T3 Code server.                                                                                                                                     |
| `host`          | string | `0.0.0.0`   | Interface to bind the T3 Code server to.                                                                                                                                |
| `serveMode`     | string | `""`        | Optional T3 runtime mode passed to `t3 serve --mode`. Empty preserves the T3 CLI default.                                                                               |
| `serviceUser`   | string | `automatic` | User account that runs T3 and owns its runtime state. Automatic selection prefers the remote user, container user, `vscode`, then `root`.                               |
| `dnsName`       | string | `""`        | Optional fully qualified DNS name exposed through the Caddy Feature.                                                                                                    |

## Example usage

```json
{
  "image": "ghcr.io/wyrd-company/devcontainers/base:noble",
  "features": {
    "ghcr.io/wyrd-company/devcontainers/t3code-server:2": {
      "port": "3773",
      "serveMode": "web",
      "dnsName": "t3.dev-environment.example.test"
    }
  }
}
```

To pin an upstream release:

```json
{
  "features": {
    "ghcr.io/wyrd-company/devcontainers/t3code-server:2": {
      "version": "0.0.42"
    }
  }
}
```

To install an explicit Wyrd Company fork release:

```json
{
  "features": {
    "ghcr.io/wyrd-company/devcontainers/t3code-server:2": {
      "packageSource": "github:wyrd-company/t3code",
      "version": "0.0.42-wyrd.2"
    }
  }
}
```

To follow the newest stable Wyrd Company fork server release:

```json
{
  "features": {
    "ghcr.io/wyrd-company/devcontainers/t3code-server:2": {
      "packageSource": "github:wyrd-company/t3code",
      "version": "latest"
    }
  }
}
```

## Package sources

With an empty `packageSource`, an exact `version` or `latest` installs the upstream release archive `t3-<version>-linux-<arch>.tar.gz` from the `v<version>` GitHub Release of `pingdotgg/t3code`, verified against that release's `SHA256SUMS`. `latest` follows the release GitHub marks as latest. Any other `version` is an npm range or dist-tag and installs `t3@<version>` through npm.

For a `github:<owner>/<repository>` source, an explicit version installs from the release tagged `server/<version>`. `latest` anonymously enumerates the exact `server/*-wyrd.*` tag namespace and selects the greatest accepted version by SemVer precedence. It does not use GitHub's repository-wide latest-release marker or tag creation time. The release archive `t3-<version>-linux-<arch>.tar.gz` is preferred; a release that carries only the npm tarball `t3-<version>.tgz` is installed through npm.

Any other non-empty `packageSource` is passed to `npm install` unchanged and takes precedence over `version`.

## Runtime layout

Every installed version is a pinned runtime at `<home>/.t3/runtime/versions/<version>/` with its executable at `t3`. The version the service runs is named in `<home>/.t3/runtime/selected-version`. An npm install is exposed through a shim in the same layout, so both kinds run the same way.

`/usr/local/bin/t3` runs the selected version, so the CLI on `PATH` always matches the service. `/usr/local/bin/t3code-server` is the service entry point: it runs the selected version's `t3 serve` with the configured host, port, mode, and `<home>/.t3` as the base directory.

## Updating

`t3code-server-update` installs a version from the configured package source, selects it, and restarts the service. The service user may run it through `sudo` and nothing else; the grant lives in `/etc/sudoers.d/t3code-server`.

```bash
sudo t3code-server-update            # latest from the package source
sudo t3code-server-update 0.0.42     # an exact version
t3code-server-update --status        # selected and installed versions
```

`--no-restart` selects the version for the next service start. `--force` reinstalls a version that is already installed. The service can also be restarted with `sudo /command/s6-svc -r /run/service/t3code-server`.

Changing `version` or `packageSource` and rebuilding the container installs that version fresh.

A T3 Code client that is newer than the server offers to update it remotely. This Feature does not support that path; the server declines it, and the update is made with `t3code-server-update` instead.

## Caddy

When both Features are selected, T3 installs after Caddy automatically. Setting `dnsName` writes `/etc/caddy/conf.d/t3code-server.caddy` and registers the name in `/etc/caddy/required-hosts.d/t3code-server.host`. Caddy waits for that name to resolve before requesting its certificate, then serves it over HTTPS and proxies to T3 on the configured loopback port. Installation fails when `dnsName` is set without a Caddy Feature version that supports DNS readiness; leave it empty to run T3 without a reverse proxy.

## Pairing

The Feature does not install Codex. Add the separate Codex CLI Feature when needed.

To mint a pairing code at any time, run the command as the service user and use the same T3 base directory as the server:

```bash
sudo -u vscode t3 auth pairing create --base-dir /home/vscode/.t3
```

Replace `vscode` and its home directory when `serviceUser` resolves to another account. T3 writes its own logs beneath `<home>/.t3/userdata/logs`; s6 sends process output to the container logs.
