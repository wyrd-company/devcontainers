## Runtime requirement

This Feature registers `sshd` as an s6-overlay 3 longrun service. The image must provide `/init` as its entrypoint, and `devcontainer.json` must set `"overrideCommand": false`.

This Feature derives from Microsoft's Dev Container SSHD Feature under the MIT License. It replaces the upstream entrypoint hook with native s6 supervision.

## Usage

While the some services automates SSH setup (e.g., when using the GitHub CLI for GitHub Codespaces), this may not be the case for other tools and services. Follow these directions to connect to the dev container from these other tools:

1. Connect to your dev container using a desktop tool or CLI that supports the dev container spec (e.g., VS Code client).

2. Put your public key in the container user's `authorized_keys` file. Password and root login are disabled, so this is the only way in. Either mount the file from `devcontainer.json`:

   ```json
   "mounts": [
     "source=${localEnv:HOME}/.ssh/id_ed25519.pub,target=/home/vscode/.ssh/authorized_keys,type=bind,readonly"
   ]
   ```

   Or copy it in from a terminal inside the container:

   ```bash
   mkdir -p ~/.ssh && chmod 700 ~/.ssh
   cat >> ~/.ssh/authorized_keys   # paste the public key, then Ctrl+D
   chmod 600 ~/.ssh/authorized_keys
   ```

   ...where `vscode` above is the user you are running as in the container.

3. Forward the SSH port (`2222` by default) to your local machine using either the `forwardPorts` property in `devcontainer.json` or the user interface in your tool (e.g., you can press <kbd>F1</kbd> or <kbd>Ctrl/Cmd</kbd>+<kbd>Shift</kbd>+<kbd>P</kbd> and select **Ports: Focus on Ports View** in VS Code to bring it into focus).

4. Use a **local terminal** (or other tool) to connect to it with the matching private key. e.g.

   ```bash
   ssh -p 2222 -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null vscode@localhost
   ```

   ...where `vscode` above is the user you are running as in the container and `2222` after `-p` is the **local address port** from step 3.

   The “-o” arguments are optional, but will prevent you from getting warnings or errors about known hosts when you do this from multiple containers/codespaces.

5. Next time you connect to your container, just repeat steps 3 and 4. The key stays authorized as long as the file is present.

### Using SSHFS

[SSHFS](https://en.wikipedia.org/wiki/SSHFS) allows you to mount a remote filesystem to your local machine with nothing but a SSH connection. Here's how to use it with a dev container.

1. Follow the steps in the previous section to ensure you can connect to the dev container using the normal `ssh` client.

2. Install a SSHFS client.

   - **Windows:** Install [WinFsp](https://github.com/billziss-gh/winfsp/releases) and [SSHFS-Win](https://github.com/billziss-gh/sshfs-win/releases).
   - **macOS**: Use [Homebrew](https://brew.sh/) to install: `brew install macfuse gromgit/fuse/sshfs-mac`
   - **Linux:** Use your native package manager to install your distribution's copy of the sshfs package. e.g. `sudo apt-get update && sudo apt-get install sshfs`

3. Mount the remote filesystem.

   - **macOS / Linux:** Use the `sshfs` command to mount the remote filesystem. The arguments are similar to the normal `ssh` command but with a few additions. For example:

     ```
     mkdir -p ~/sshfs/devcontainer
     sshfs "vscode@localhost:/workspaces" "$HOME/sshfs/devcontainer" -p 2222 -o follow_symlinks -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null -C
     ```

     ...where `vscode` above is the user you are running as in the container (e.g. `codespace`, `vscode`, `node`, or `root`) and `2222` after the `-p` is the same local port you used in the `ssh` command in step 1.

   - **Windows:** Press Window+R and enter the following in the "Open" field in the Run dialog:

     ```
     \\sshfs.r\vscode@localhost!2222\workspaces
     ```

     ...where `vscode` above is the user you are running as in the container and `2222` after the `!` is the same local port you used in the `ssh` command in the previous section.

4. Your dev container's filesystem should now be available in the `~/sshfs/devcontainer` folder on macOS or Linux or in a new explorer window on Windows.

## OS Support

This Feature should work on recent versions of Debian/Ubuntu-based distributions with the `apt` package manager installed.

`bash` is required to execute the `install.sh` script.

## Persisted state

This Feature mounts a named Docker volume into the dev container so the SSH server fingerprint is stable across rebuilds:

- `sshd-etc-ssh-host-keys-${devcontainerId}` → `/etc/ssh/keys`

Host keys are generated at image build time and copied into this volume on first boot. Rebuilding the container (which re-runs the Feature's install step and regenerates the build-time keys) does not change the fingerprint because the volume takes precedence. To rotate the host keys, remove the volume:

```bash
docker volume rm sshd-etc-ssh-host-keys-<devcontainerId>
```

Because the fingerprint becomes stable, the `-o StrictHostKeyChecking=no` flags in the usage examples above are no longer required for reconnecting to the same dev container and can be dropped once you have accepted its host key.
