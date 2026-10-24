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
