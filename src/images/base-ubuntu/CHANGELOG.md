# Changelog

## 1.1.0

### Features

- A D-Bus session bus for the `vscode` user runs as the `dbus-session` s6 service, and `DBUS_SESSION_BUS_ADDRESS` points every process at it. D-Bus clients such as `gh`'s keyring lookup and VS Code no longer start a new `dbus-daemon` on each call that never exits, which used up the host's per-user inotify instances and froze long-running containers. The image installs `dbus-daemon` but not `dbus-launch`.

## 1.0.0

### Features

- An Ubuntu image that is based on the Microsoft Dev Container base image. It keeps the upstream tools, the non-root `vscode` user and the Dev Container metadata.
- s6-overlay 3 runs as PID 1. Add services as s6-rc definitions.
- Variants `noble` (Ubuntu 24.04) and `resolute` (Ubuntu 26.04), each for `amd64` and `arm64`. Each tag names its Ubuntu release, so a tag never changes to another release.
- The `vscode` user has passwordless `sudo` only for `apt-get` and `apt` update and install, and for s6-overlay service control (`s6-svc`, `s6-svstat` and `s6-rc`). All other `sudo` commands are denied.
