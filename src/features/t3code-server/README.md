# T3 Code Server

Installs T3 Code as a pinned release runtime and runs its native service launcher under s6-overlay 3 as the selected service user. Connected clients can update the server in place. `t3code-server-update` provides local maintenance. Runtime state remains in the service user's home directory.

The Feature requires a Debian/Ubuntu image with s6-overlay 3 already installed. Release archives are self-contained; Node.js 24 is supplied through the official Dev Container Node Feature for versions installed through npm.

## Options

| Option        | Type   | Default     | Description                                                                                                                                                                          |
| ------------- | ------ | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `version`     | string | `latest`    | T3 Code version. An exact version or `latest` installs the upstream release archive; `latest` follows GitHub's latest upstream release. Any other value is an npm range or dist-tag. |
| `port`        | string | `3773`      | Port exposed by the T3 Code server.                                                                                                                                                  |
| `host`        | string | `0.0.0.0`   | Interface to bind the T3 Code server to.                                                                                                                                             |
| `serveMode`   | string | `""`        | Optional T3 runtime mode passed to `t3 serve --mode`. Empty preserves the T3 CLI default.                                                                                            |
| `serviceUser` | string | `automatic` | User account that runs T3 and owns its runtime state. Automatic selection prefers the remote user, container user, `vscode`, then `root`.                                            |
| `dnsName`     | string | `""`        | Optional fully qualified DNS name exposed through the Caddy Feature.                                                                                                                 |

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

## Versions

An exact `version` or `latest` installs the release archive `t3-<version>-linux-<arch>.tar.gz` from the `v<version>` GitHub Release of `pingdotgg/t3code`, verified against that release's `SHA256SUMS`. `latest` follows the release GitHub marks as latest. Any other `version` is an npm range or dist-tag and installs `t3@<version>` through npm.

## Runtime layout

Every installed version is a pinned runtime at `<home>/.t3/runtime/versions/<version>/` with its executable at `t3`. An npm install keeps its own npm prefix inside its version directory and exposes its platform binary through a shim.

For runtimes that pass upstream's launcher protocol preflight, s6 supervises `<home>/.t3/runtime/service-launcher __service-launcher`. This symlink points to a fixed installed runtime. The launcher starts the server version recorded in T3's native `runtime/service-state.json`; remote updates change the server version while retaining the launcher. The launcher is registered in T3's native `runtime/launchers` file so runtime cleanup retains it.

`/usr/local/bin/t3` reads the native active version, so the CLI follows successful updates and rollbacks. Older runtimes without the compatible launcher protocol run `t3 serve` directly and use `runtime/selected-version`. Exact pins and npm ranges support both paths.

`/usr/local/bin/t3code-server` resolves the configured host, port, mode and base directory. The native launcher accepts no server flags, so the wrapper supplies `T3CODE_HOST`, `T3CODE_PORT`, `T3CODE_MODE` and `T3CODE_HOME` to its children. This is an exception to the service flags convention. The existing `T3CODE_HOST`, `T3CODE_PORT` and `T3CODE_SERVE_MODE` runtime overrides are supported; `T3CODE_HOME` remains the configured service user's `.t3` directory. Direct-server runtimes receive command-line flags. T3's user-owned `service.env` may override host and port; upstream reserves its managed home and launcher context.

## Updating

A connected T3 client offers **Update server** when the launcher supports it. T3 downloads a release archive, verifies its checksum and preflight, then asks its launcher to replace the server. The launcher snapshots SQLite, starts the replacement as a trial, and commits after successful startup. A failed trial restores the database and previous server. Files outside SQLite are outside that rollback boundary. Remote updates run as the service user without sudo and remain selected after an s6 or container restart.

Remote updates require a newer server version and a compatible launcher protocol. If an update requires a newer launcher, run the local maintenance command on the container. Legacy direct-server runtimes require local maintenance as well. To enable the native launcher for an existing persisted installation whose version is already current, run `sudo t3code-server-update --force`. This explicitly reinstalls and selects the runtime; ordinary startup preserves its existing selector.

```bash
sudo t3code-server-update            # the latest upstream release, including its launcher
sudo t3code-server-update 0.0.42     # an exact version, including a downgrade
t3code-server-update --status        # active, queued and installed versions
```

The version is `latest` or an exact version; a `v` prefix is accepted. Local updates install release archives only, so npm ranges and dist-tags are not accepted. Changing the Feature's `version` and rebuilding installs that version into the image. A persisted `.t3` mount masks the image's runtime files and retains its active version; use local maintenance to change that selection.

Local maintenance downloads and verifies a separate staged runtime before stopping the service. It queues that runtime, waits for the launcher and child to stop, then starts the service. Startup publishes the runtime and selects its matching launcher before running it. The CLI and status continue to show the native active version until maintenance is applied. Local maintenance deliberately selects the requested version; it does not use the remote update's database trial or rollback. Downgrades must be compatible with the stored database.

`--no-restart` queues the runtime for the next service start without changing the live server or CLI. The queue records the originating active version. If a native update changes that version before maintenance applies, startup discards the stale request rather than selecting an older server. Installed runtimes are reused unless `--force` requests a fresh download and replacement while the service is stopped. Local maintenance leaves an operator-stopped service stopped. A pending native update recovers before queued local maintenance; restart again after recovery to apply the queue if its originating version remains active. The stop wait uses s6's default with no deadline; T3's launcher owns graceful child termination. Superseded queued downloads are removed during preparation.

`--status` reports installed runtimes and service supervision even when selection is missing or invalid. It returns a nonzero status and reports the selection as unavailable rather than selecting a fallback.

The service user may run `t3code-server-update` through `sudo`; the grant is limited to that command in `/etc/sudoers.d/t3code-server`. Downloads, staging and runtime selection run as the service user. Root controls s6 only. As root, restart manually with `/command/s6-svc -r /run/service/t3code-server`.

To preserve state across rebuilds, configure a mount for the service user's entire `<home>/.t3` directory, including `runtime` and `userdata`. A named volume is populated from the image on its first use. A bind mount must already contain an initialized runtime tree. The Feature declares no persistent mount.

## Caddy

When both Features are selected, T3 installs after Caddy automatically. Setting `dnsName` writes `/etc/caddy/conf.d/t3code-server.caddy` and registers the name in `/etc/caddy/required-hosts.d/t3code-server.host`. Caddy waits for that name to resolve before requesting its certificate, then serves it over HTTPS and proxies to T3 on the configured loopback port. Installation fails when `dnsName` is set without a Caddy Feature version that supports DNS readiness; leave it empty to run T3 without a reverse proxy.

## Pairing

The Feature does not install Codex. Add the separate Codex CLI Feature when needed.

To mint a pairing code at any time, run the command as the service user and use the same T3 base directory as the server:

```bash
sudo -u vscode t3 auth pairing create --base-dir /home/vscode/.t3
```

Replace `vscode` and its home directory when `serviceUser` resolves to another account. T3 writes its own logs beneath `<home>/.t3/userdata/logs`; s6 sends process output to the container logs.

## Trademarks

This feature is not affiliated with or endorsed by T3 Tools Inc. T3 Code and its logo are trademarks of T3 Tools Inc. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the T3 mark from [T3Mark.svg](https://github.com/pingdotgg/t3code/blob/d414cb51032f302c268ebd11a486240139dfd3c0/apps/mobile/assets/widget/T3Mark.svg) (MIT). No trademark terms are published.
