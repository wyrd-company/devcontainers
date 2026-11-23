---
base: minor
base-docs: minor
---

Add `bao-secret`, which reads a field of an OpenBao KV version 2 secret through `BAO_ADDR` or `VAULT_ADDR` with the image's `curl` and `jq`, and answers Vector's `exec` secret backend protocol. It never writes a secret to disk, the environment or a command line.
