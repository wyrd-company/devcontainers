---
title: Services
product: base
order: 3
---

s6-overlay is PID 1. Its `/init` entrypoint starts the s6 supervision tree, and `/command/s6-pause` is the default command.

Add native s6-rc service definitions under `/etc/s6-overlay/s6-rc.d` and include services in `/etc/s6-overlay/user-bundles.d/user/contents.d`. Services should depend on the `base` bundle unless they intentionally need to start earlier.

The `vscode` user can control services with sudo:

```bash
sudo /command/s6-svc -r /run/service/<service>
sudo /command/s6-svstat /run/service/<service>
sudo /command/s6-rc -a list
```

## Container health

Docker reports `starting` while s6 starts the configured services. The check waits for startup oneshots, then checks that the supervised services are running and have reported readiness where configured. Two exits within the past minute fail the service check, even while the process is running again. Legacy services configured to start by hand with a `down` file are skipped.

Docker gives startup a two-minute grace period by default. It starts counting consecutive failures after the grace period or the first successful check, whichever comes first. Three consecutive failures make the container `unhealthy`. A successful check makes it `healthy`, including after a late start or a service restart. Override the grace period with Docker's `--health-start-period` or Compose's `healthcheck.start_period`. To see recent probe output, look under `.State.Health.Log` in `docker inspect`.

Docker health requires the image's `/init` entrypoint. If you bypass it, disable the inherited check with `HEALTHCHECK NONE` in a derived Dockerfile, `docker run --no-healthcheck`, or Compose's `healthcheck.disable: true`.

Longruns can report readiness to s6 via `notification-fd`, as D-Bus does. This also affects when dependent services start. For readiness that affects only Docker health, install a trusted executable as `data/healthcheck` in the s6 service definition. It must exit zero when the running service is ready. Caddy uses this check to wait for DNS and configuration loading while the rest of the container starts independently.

## D-Bus session bus

The image runs one [D-Bus](https://www.freedesktop.org/wiki/Software/dbus/) session bus for the `vscode` user as the `dbus-session` service. Its socket is `/run/dbus-session/bus`, and the image sets `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/dbus-session/bus` for every process in the container: shells, `docker exec`, editors and s6 services.

Without that address, a D-Bus client such as a libsecret keyring, a Go keyring library (used by `gh`), or VS Code starts a new `dbus-daemon` through `dbus-launch` on every call, and the daemon never exits. In a long-running container these pile up, one per call, until they use the per-user inotify instances shared by every container on the host. With the address set, clients connect to the one bus instead, and fail without starting a daemon when it is down.

- Only `vscode` may connect. Other users, including root, are refused immediately.
- The image does not install `dbus-launch` (Ubuntu's `dbus-x11`). Another package manager can still add one. A process that clears its environment, such as a command run through `sudo`, then autolaunches again; keep `DBUS_SESSION_BUS_ADDRESS` in its environment.
- To check the bus:

```bash
dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.GetId
```
