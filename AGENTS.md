# Devcontainers

This repository contains devcontainer images, features, and templates in use by Wyrd Company. They provide critical _3rd party_ dependencies. Wyrd Company products can and should publish devcontainer features from those repositories.

Devcontainers at Wyrd Company are _long running_ and often multi-repo.

## General Principles/Invariants

- **Services run under S6 overlay** - the base Ubuntu image has S6 overlay as its PID1 init entrypoint. 3rd party features we use that overwrite init will be re-created in this repo and track the upstream feature. All features can assume the base image published by this repo is a pre-requisite.
- **`vscode` is the container user** - we retain the Microsoft `vscode` convention as VisualStudio Code is the default IDE in use by Wyrd Company and it is the convention of the upstream image.
- **We balance security hardening with ergonomics** - the balance is not automatically one way or the other, but always a consideration.
- **`sudo` access is restricted** - specific features may add specific commands to `/etc/sudoers.d/<feature>`, but never `ALL`.
- **Features are cooperative by default** - a feature should leverage other features when present. Example: A feature that provides a web user interface should expose that web site through the Caddy feature when the Caddy feature is installed.
- **Agentic harnesses and tools must be upgradeable without a container rebuild** - Agentic engineering is a fast moving space and these applications update frequently, and often require the latest updates to provide complete access to services, so we must not restrict their ability to update in-place. The option to pin to a version should still exist.
- **Carefully expose our opinionated way of working** - while these images, features, and templates are built for Wyrd Company use, they are made public because they may be useful to others. They are built in a opinionated way, but where possible we temper the expression of that opinion. This means, where possible, we use defaults where possible for our own way of working, but allow configuration so others can have a different opinion.
- **We deprecate and remove features we are no longer actively using** - things change, we learn and adapt. This may mean a feature we were using yesterday is no longer needed. Since there is a maintenance burden for everything we publish, we deprecate those we are no longer using. The repo is public, other users are free to fork our work.
- **Features are self-contained** - every feature has its own `install.sh`. Helpers are copied into a per-feature `common.sh`. Nothing is shared across feature directories.
- **Installers run as root and fail fast** - each installer checks root, the Debian/Ubuntu family, the s6-overlay 3 paths (service features), and the architecture before it changes anything.
- **Downloads are verified** - release archives are checked against published SHA256 checksums. Apt sources add a keyring. The base image checks s6-overlay checksums the same way.
- **Version pinning is validated and normalized** - `latest` is the default. Pinned versions must match semver. The upstream `v` prefix is accepted and stripped. The installed version is verified after install.
- **Features do not persist state behind the user's back** - configuration and state stay in the tool's native paths. Mounts that survive a rebuild are documented in `NOTES.md` and `README.md` for the user to configure. A feature declares a mount only when the feature cannot work without it, and every declared mount is documented.
- **Services bind to IPv4 loopback by default** - `localhost` is normalized to `127.0.0.1`. Caddy proxies only over loopback. Exposure beyond the container is opt-in through `dnsName`.
- **Services run with the user's full environment** - the s6 run script uses `s6-setuidgid` and sets `HOME` and `USER`, so that workflows and agents get the user's Git, SSH, and tools. Runtime tests assert this.
- **Configuration is passed as command-line flags** - flags override the tool's own environment variables and config files. Runtime tests assert that environment variables cannot override the flags.
- **Failure is loud, not substituted** - Moby installs nothing when its package set is missing. Caddy keeps the last good config when a reload fails.
- **Upstream forks carry provenance** - forked features keep the upstream license header, `LICENSES/` holds the upstream license text, and `NOTES.md` says what was changed and why.
- **Multi-arch is required** - images and binary features support `amd64` and `arm64`. Unsupported architectures fail at install.
- **Image tags never silently change release** - rolling tags are per Ubuntu codename and version. Every build also gets a dated immutable tag, and twelve are retained for rollback.
- **Follow and document conventions** - as we add features to the repo conventions will naturally develop. Document them in the `Conventions` section of the AGENTS.md file in the repo as they are discovered or change.

## Conventions

- Features that install a service use S6-overlay.
- Any feature that installs a service exposes a `serviceUser` option. The default value is `automatic` which means it runs as the remote user, container user, `vscode`, then `root` in that order, or the specified user if another value is provided.
- Add the `dnsName` option to features that expose a web UI to enable reverse proxying the web UI through the Caddy feature when it is also installed in the devcontainer.
- Document required mounts instead of adding them to the `devcontainer-feature.json`.
- Feature directory layout: `devcontainer-feature.json`, `install.sh`, `NOTES.md`, `README.md`, optional `common.sh`. `NOTES.md` is the short operational note. `README.md` is the full page with an Options table.
- Every feature declares `installsAfter` common-utils so that the container user exists. A feature that writes Caddy fragments also declares `installsAfter` the Caddy feature so that its directories exist. `installsAfter` is ordering only, so the installer still validates the prerequisite.
- A feature exposes a `version` option only when it installs a versioned artifact. The default is `latest`. A feature that installs a distribution package tracks the distribution and has no `version` option.
- Option validation rejects newlines, braces, and other characters that could break generated config files.
- Generated launcher scripts live in `/usr/local/bin/<feature>-service`. The s6 service is a `longrun` under `/etc/s6-overlay/s6-rc.d/<feature>` that depends on `base` and is registered in the `user` bundle.
- Caddy integration writes `/etc/caddy/conf.d/<feature>.caddy` and `/etc/caddy/required-hosts.d/<feature>.host`.
- User-local CLI tools install under the user's `~/.local/bin` and are symlinked into `/usr/local/bin`.
- Installers log with a `[feature]` prefix and clean apt lists at the end.
- Tests: `test/features/<feature>/test.sh` for the autogenerated scenario, `scenarios.json` plus named scripts for declared scenarios, `runtime.Dockerfile` plus `scripts/test-<feature>-runtime.sh` for s6 runtime acceptance. Runtime tests assert the process owner, its environment, and rejected inputs.
- CI matrix: CLI features test on both a plain Debian image and the Microsoft base. Service features test only on the published base image.
- Test values use `example.test` domains and `sample-` prefixed values.
- Semver in `devcontainer-feature.json` is bumped by hand. Major bumps change the published tag, as with `opencodex:2`.
