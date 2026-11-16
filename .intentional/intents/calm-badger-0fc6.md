---
base: minor
---

A D-Bus session bus for the `vscode` user runs as the `dbus-session` s6 service, and `DBUS_SESSION_BUS_ADDRESS` points every process at it. D-Bus clients such as `gh`'s keyring lookup and VS Code no longer start a new `dbus-daemon` on each call that never exits, which used up the host's per-user inotify instances and froze long-running containers. The image installs `dbus-daemon` but not `dbus-launch`.
