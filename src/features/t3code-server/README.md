# T3 Code Server

Installs T3 Code as a pinned release runtime and runs it through the T3 Code service launcher (`t3 __service-launcher`) as a native s6-overlay 3 service. The launcher supervises `t3 serve` as the selected service user and applies updates that a T3 Code client requests from the server. Runtime state remains in the service user's home directory.

The Feature requires a Debian/Ubuntu image with s6-overlay 3 already installed. Release archives are self-contained; Node.js 24 is supplied through the official Dev Container Node Feature for npm package sources.

## Options

| Option           | Type   | Default     | Description                                                                                                                                         |
| ---------------- | ------ | ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `version`        | string | `latest`    | T3 Code version. With upstream, `latest` follows GitHub's latest upstream release. With a GitHub source, `latest` selects the greatest stable fork server tag by SemVer precedence. |
| `packageSource`  | string | `""`        | Optional GitHub repository source, npm package spec, or tarball URL. Empty installs upstream T3 Code.                                               |
| `releaseBaseUrl` | string | `""`        | Optional base URL for release archives the server downloads when a client updates it (`T3CODE_RELEASE_BASE_URL`). Empty derives it from the source. |
| `port`           | string | `3773`      | Port exposed by the T3 Code server.                                                                                                                 |
| `host`           | string | `0.0.0.0`   | Interface to bind the T3 Code server to.                                                                                                            |
| `serveMode`      | string | `""`        | Optional T3 runtime mode (`T3CODE_MODE`). Empty preserves the T3 CLI default.                                                                       |
| `serviceUser`    | string | `automatic` | User account that runs T3 and owns its runtime state. Automatic selection prefers the remote user, container user, `vscode`, then `root`.           |
| `dnsName`        | string | `""`        | Optional fully qualified DNS name exposed through the Caddy Feature.                                                                                |

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

Every installed version is a pinned runtime at `<home>/.t3/runtime/versions/<version>/` with its executable at `t3`. The version the service runs is recorded in `<home>/.t3/runtime/service-state.json`. An npm install is exposed through a shim in the same layout, so the launcher treats both kinds alike.

`/usr/local/bin/t3` runs the selected version, so the CLI on `PATH` always matches the service. `/usr/local/bin/t3code-server` is the service entry point: it exports `T3CODE_HOME`, `T3CODE_PORT`, `T3CODE_HOST`, `T3CODE_MODE`, and `T3CODE_RELEASE_BASE_URL`, then starts the selected version's launcher.

The launcher requires T3 Code 0.0.42 or newer. Each release's launcher speaks one launcher protocol and reads only state written for it; selecting a version records the protocol that version answers its own preflight with, and a service restart starts that version's launcher.

## Updating

**From a client.** A T3 Code client that is newer than the server offers to update it. The server downloads `t3-<client version>-linux-<arch>.tar.gz` and `SHA256SUMS` from `<releaseBaseUrl>/v<client version>/`, verifies it, stages it as a pinned runtime, and hands off to the launcher, which restarts `t3 serve` on the new version and rolls back if it fails to come up. With an upstream install the default base URL is upstream's GitHub Releases. With a GitHub source the default is `https://github.com/<owner>/<repository>/releases/download/server`, so a client-requested version resolves to the fork release `server/v<version>`; a fork that does not publish that release declines the update instead of installing upstream over the fork.

A release that requires a newer launcher protocol than the running launcher declines a client-driven update with "This release requires a newer T3 Code service launcher"; update it inside the container instead, which restarts the service on the new launcher.

**Inside the container.** `t3code-server-update` installs a version from the configured package source, selects it, and restarts the service:

```bash
sudo t3code-server-update            # latest from the package source
sudo t3code-server-update 0.0.42     # an exact version
sudo t3code-server-update --status   # selected and installed versions
```

`--no-restart` selects the version for the next service start. `--force` reinstalls and selects a version even while the launcher has an update pending. The service can also be restarted with `sudo /command/s6-svc -r /run/service/t3code-server`.

**Rebuild.** Changing `version` or `packageSource` and rebuilding the container installs that version fresh.

## Caddy

When both Features are selected, T3 installs after Caddy automatically. Setting `dnsName` writes `/etc/caddy/conf.d/t3code-server.caddy` and registers the name in `/etc/caddy/required-hosts.d/t3code-server.host`. Caddy waits for that name to resolve before requesting its certificate, then serves it over HTTPS and proxies to T3 on the configured loopback port. Installation fails when `dnsName` is set without a Caddy Feature version that supports DNS readiness; leave it empty to run T3 without a reverse proxy.

## Pairing

The Feature does not install Codex. Add the separate Codex CLI Feature when needed.

To mint a pairing code at any time, run the command as the service user and use the same T3 base directory as the server:

```bash
sudo -u vscode t3 auth pairing create --base-dir /home/vscode/.t3
```

Replace `vscode` and its home directory when `serviceUser` resolves to another account. T3 writes its own logs beneath `<home>/.t3/userdata/logs`; s6 sends launcher and server output to the container logs.
