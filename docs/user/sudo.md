---
title: sudo
product: base
order: 4
---

The `vscode` user has passwordless `sudo` for two purposes only:

- Package installation: `apt-get update`, `apt-get install`, and the `apt` equivalents. `DEBIAN_FRONTEND` is passed through. The operation must be the first word that is not an option. Options that take a value use the `-o value`, `-ovalue`, or `--name=value` form. Package names must not end in `-` or `_`, which apt treats as remove and purge.
- s6-overlay service control: `s6-svc` and `s6-svstat` on `/run/service/*`, and `s6-rc`.

```bash
sudo apt-get update && sudo apt-get install -y --no-install-recommends jq
sudo /command/s6-svc -r /run/service/<service>
```

Every other command is denied. Image builds and Dev Container Features still run as root, so they are unaffected. Do not add the `common-utils` Feature on top of this image; it may reinstate unrestricted sudo for the user it manages.

The policy lives in `/etc/sudoers.d/vscode`. `apt-get install` accepts local `.deb` files and `-o` options, so this is a guardrail against casual privilege use rather than a hard security boundary.
