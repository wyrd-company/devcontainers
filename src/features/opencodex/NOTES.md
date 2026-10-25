OpenCodex version 2 defaults to Remote Hub client mode; version 1 ran a local proxy by default. Persist a separate `${HOME}/.opencodex` and Codex home for each dev container, then run `ocx connect` once to enroll it. An s6 oneshot runs `ocx sync` on later starts when the client is connected and owns its saved token.

Set `mode=standalone` to run the local proxy and dashboard under s6-overlay. In standalone mode, `ocx update` holds the supervised proxy while it replaces the user-owned package, then s6 restarts it.

Logo: the OpenCodex mark from [icon.svg](https://github.com/lidge-jun/opencodex/blob/9f0d40a25f8b842c33ab233d466d0bd991d86052/desktop/src-tauri/icons/icon.svg) (MIT), without its app-icon backdrop. No trademark terms are published. Used here only to identify the upstream project.
