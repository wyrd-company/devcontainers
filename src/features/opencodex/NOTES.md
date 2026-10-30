[OpenCodex](https://opencodex.me/) version 2 defaults to Remote Hub client mode; version 1 ran a local proxy by default. Persist a separate `${HOME}/.opencodex` and [Codex](https://github.com/openai/codex) home for each dev container, then run `ocx connect` once to enroll it. An [s6-overlay](https://github.com/just-containers/s6-overlay) oneshot runs `ocx sync` on later starts when the client is connected and owns its saved token.

Set `mode=standalone` to run the local proxy and dashboard under [s6-overlay](https://github.com/just-containers/s6-overlay). In standalone mode, `ocx update` holds the supervised proxy while it replaces the user-owned package, then s6 restarts it.

When the [Ansible](https://www.ansible.com/) Feature is installed, the OpenCodex service starts only after the `ansible-setup` s6-rc oneshot finishes, and does not start if it fails. Without Ansible, startup does not change. In client mode it is the `opencodex-client-sync` oneshot.

## Trademarks

This feature is not affiliated with or endorsed by the OpenCodex contributors. OpenCodex and its logo are trademarks of the OpenCodex contributors. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the OpenCodex mark from [icon.svg](https://github.com/lidge-jun/opencodex/blob/9f0d40a25f8b842c33ab233d466d0bd991d86052/desktop/src-tauri/icons/icon.svg) (MIT), without its app-icon backdrop. No trademark terms are published.
