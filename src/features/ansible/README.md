# Ansible

Installs [Ansible](https://www.ansible.com/) from the distribution's `ansible-core` package and applies a playbook to the container each time it starts. The Feature requires a Debian/Ubuntu image with [s6-overlay](https://github.com/just-containers/s6-overlay) 3 and supports `amd64` and `arm64`. It tracks the distribution's Ansible release and has no `version` option.

The playbook source and the playbook live outside this repository. The Feature installs three things:

| Item                          | Purpose                                                                                       |
| ----------------------------- | --------------------------------------------------------------------------------------------- |
| `ansible-setup` s6 oneshot    | Runs at container startup in the `user` bundle. It succeeds only after the playbook succeeds. |
| `/usr/local/bin/ansible-sync` | Updates the playbook source and applies the playbook again.                                   |
| `/etc/ansible-setup/settings` | The validated, non-secret option values that the two commands read.                           |

## Configuration

Set `source` to a [Git](https://git-scm.com/) repository, or to a local directory, and `playbook` to the playbook inside it:

```json
{
  "image": "ghcr.io/wyrd-company/devcontainers/base:noble",
  "overrideCommand": false,
  "features": {
    "ghcr.io/wyrd-company/devcontainers/ansible:1": {
      "source": "git@example.test:sample-team/sample-playbooks.git",
      "playbook": "container.yml",
      "ref": "main"
    }
  }
}
```

Without `source` the Feature only installs Ansible: the oneshot reports that nothing is configured and succeeds, and `ansible-sync` fails.

### Git source

- The checkout is a shallow clone in `checkoutDir`, owned by the service user. Every run fetches `ref` and moves the checkout to it, discarding changes to tracked files. Untracked files stay.
- `ref` is a branch, tag or commit. Empty tracks the remote's default branch.
- `https://`, `ssh://`, `file://` and `user@host:path` sources are accepted. A URL that embeds a password or token is rejected, and Git never prompts for credentials. Use SSH for a private repository.
- SSH access comes from the SSH agent that the container provides. [Wyrwood](https://wyrd.foo/tools/wyrwood/) provides it; see [below](#wyrwood-and-the-vault-socket).
- When `GIT_SSH_COMMAND` is not set in the container, Git runs `ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new`. [OpenSSH](https://www.openssh.com/) records a host key the first time it sees it in the service user's `known_hosts` and refuses a changed key. Set `GIT_SSH_COMMAND` in `containerEnv`, or mount a `known_hosts` file, for a different policy.
- Submodules are not fetched.

### Local directory source

An absolute `source` path, such as a bind mount, is used in place. The Feature does not clone, copy, fetch or modify it, so `ref` and `checkoutDir` do not apply, and `ref` is rejected. A missing directory fails the run. Edit the directory on the host and run `ansible-sync` to apply the change.

### Inventory, requirements and arguments

- `inventory` is a path in the source. Empty runs against `localhost`, which is the container itself. The run always uses `--connection local`; an `args` value can override it.
- `requirements` is a roles and collections file in the source. `ansible-galaxy install -r` runs before each playbook run and installs into Ansible's native locations under the service user's home. It forces the listed roles and their dependencies to reinstall, so a changed version in the file replaces the installed one, and every run needs the role and collection sources to be reachable.
- `args` holds extra `ansible-playbook` arguments, split on spaces, such as `--tags base -e sample_flag=true`. Quotes, braces and other shell characters are rejected. Use `-e @file.yml` for structured variables.
- `ansible-playbook` runs with the source directory as its working directory, so an `ansible.cfg` there applies. The flags above take precedence over the container's `ANSIBLE_*` variables.

## Startup and `ansible-sync`

At every container start the `ansible-setup` oneshot updates the source and applies the playbook, so the playbook must be idempotent. `ansible-sync` does the same work on demand, for example when a release event reports a change to the playbook repository. A lock serializes the two: a call that arrives while the other runs waits for it.

The oneshot and `ansible-sync` stop and fail when:

- the repository cannot be fetched. The checkout stays as it was, and the Feature does not run a stale playbook;
- the playbook, inventory or requirements file is missing;
- `ansible-galaxy` or `ansible-playbook` fails.

A failed oneshot does not stop the container. Services that depend on `ansible-setup` do not start until a later run succeeds. A failed startup does not retry by itself. After you fix the cause, run `ansible-sync` to check the result. It does not mark the oneshot as up, so services that wait for `ansible-setup` stay down until you run `s6-rc -u change user` as root, which retries `ansible-setup` and starts its dependents, or restart the container. The Feature sets no timeout, so an unreachable but not refusing repository waits on Git's own network timeouts.

`ansible-sync` runs as the service user. Called by root it changes to that user, and called by any other user it fails unless `sudoUser` names that user. With the default `serviceUser` of `root`, run it as root, for example with `docker exec --user root <container> ansible-sync`, or set `sudoUser`.

```bash
ansible-sync
```

### Running `ansible-sync` with `sudo`

`sudoUser` is empty by default, so the Feature adds no sudo rule. Set it to a user name, or to `automatic` for the first of the remote user, container user and `vscode` that is not root, and the Feature writes `/etc/sudoers.d/ansible`:

```text
vscode ALL=(root) NOPASSWD: /usr/local/bin/ansible-sync ""
```

That user can run `sudo ansible-sync` and nothing else as root. The empty `""` means no arguments, so sudo refuses `sudo ansible-sync --startup` and every other argument. The command runs the configured playbook as `serviceUser`, so the grant gives that user the rights of the service user (root by default) over whatever the playbook does. The user cannot choose another playbook or source: only root can edit the settings, and a Git checkout of the default `serviceUser` belongs to root. A local directory source is different. Anyone who can write to that directory can change what the playbook does, so keep it read-only for the sudo user.

sudo gives a command a minimal environment, so `ansible-sync` loads the container environment, as it does at startup, and drops sudo's own variables. The playbook sees the same `SSH_AUTH_SOCK`, `VAULT_ADDR` and other variables as at startup, and nothing the caller set. The base image restricts `vscode` to a few commands in `/etc/sudoers.d/vscode`; this rule adds one more and keeps `scripts/check-sudo-no-all.sh` passing. The image must contain sudo; the installer fails when `visudo` is missing.

## Service user

The default is `root`, so a playbook can install packages and write system configuration: the `vscode` user's sudo rights in the Wyrd base image do not allow Ansible's `become`. A playbook that configures the `vscode` user can use `become_user: vscode`. `automatic` prefers the remote user, container user, `vscode`, then `root`, and a user name selects that user. The command sets `HOME`, `USER` and `LOGNAME` for the service user. The Dev Containers CLI can change that user's ID to match the host user's after the Feature installs; each root run, including startup, gives the lock directory and the top of the Git checkout (not their contents) to the user's current ID. For that, a non-root service user needs a `checkoutDir` below directories that only root can change, which the installer enforces. The path may not pass through a symbolic link. The repair does not touch files inside those directories: if a persisted checkout or lock file keeps the old ID, Git reports dubious ownership or the lock cannot open, and every run fails until you recreate the checkout (remove `checkoutDir`'s contents) or give the files to the user as root.

## Wyrwood and the Vault socket

The playbook runs with the container's environment, unchanged. When the container is bound to [Wyrwood](https://wyrd.foo/tools/wyrwood/), its environment holds `SSH_AUTH_SOCK`, which points at the SSH agent socket, and `VAULT_ADDR`, which points at the [OpenBao](https://openbao.org/) API socket. Git uses the agent socket to read private repositories. A playbook reads the Vault address from its environment, for example `lookup('env', 'VAULT_ADDR')`.

The Feature does not rename, add or remove any of these variables. It does not require the OpenBao Agent Feature, store a credential, write a secret file or accept a secret as an option. The Wyrwood socket directory is a bind mount that you configure in `devcontainer.json`; see the Wyrwood documentation. [Trowel](https://wyrd.foo/tools/trowel/) can call `ansible-sync` to apply a change after a release.

## Startup order

The `ansible-setup` oneshot depends on the `base` bundle and nothing else. This Feature does not add a dependency to any other service. A service Feature that needs the converged configuration declares `installsAfter` for this Feature and adds an s6-rc dependency on `ansible-setup` when that service exists.

## Options

| Option         | Type   | Default                           | Description                                                                                                              |
| -------------- | ------ | --------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `source`       | string | `""`                              | Git repository URL or absolute path of a local directory. Empty installs Ansible only.                                   |
| `playbook`     | string | `site.yml`                        | Playbook path relative to the source.                                                                                    |
| `ref`          | string | `""`                              | Branch, tag or commit to track. Empty tracks the remote's default branch.                                                |
| `inventory`    | string | `""`                              | Inventory path relative to the source. Empty runs against `localhost`.                                                   |
| `requirements` | string | `""`                              | Roles and collections requirements file relative to the source.                                                          |
| `args`         | string | `""`                              | Extra `ansible-playbook` arguments, split on spaces.                                                                     |
| `checkoutDir`  | string | `/var/lib/ansible-setup/checkout` | Absolute path of the Git checkout. It must not contain or sit inside the lock directory `/var/lib/ansible-setup/lock.d`. |
| `serviceUser`  | string | `root`                            | User that runs the playbook. `automatic` prefers the remote user, container user, `vscode`, `root`.                      |
| `sudoUser`     | string | `""`                              | User that may run `sudo ansible-sync` and nothing else. Empty adds no sudo rule. `automatic` picks a non-root user.      |

Option values are fixed when the container image is built, validated, and rejected when they hold newlines, quotes, braces or other characters that could break the generated settings.

## Locations

| Purpose                   | Location                                                      |
| ------------------------- | ------------------------------------------------------------- |
| Settings                  | `/etc/ansible-setup/settings`                                 |
| Lock                      | `/var/lib/ansible-setup/lock.d/lock`                          |
| Default checkout          | `/var/lib/ansible-setup/checkout`                             |
| s6 service                | `/etc/s6-overlay/s6-rc.d/ansible-setup`                       |
| Startup and sync commands | `/usr/local/bin/ansible-setup`, `/usr/local/bin/ansible-sync` |
| sudo rule (`sudoUser`)    | `/etc/sudoers.d/ansible`                                      |

The Feature declares no mounts. Roles and collections install under the service user's `~/.ansible`. Persist the checkout directory or that directory with a bind mount only if you want them to survive a rebuild.

## Trademarks

This feature is not affiliated with or endorsed by Red Hat, Inc. or the Ansible project. Ansible and its logo are trademarks of Red Hat, Inc. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the Ansible community mark (Mango) from the [ansible/logos](https://github.com/ansible/logos) repository, licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) and subject to its [trademark policy](https://github.com/ansible/logos/blob/main/TRADEMARKS.md).
