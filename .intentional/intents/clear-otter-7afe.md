---
vector: patch
---

The service runs when the Dev Container CLI changes the user's UID and GID to match the host user. At start, it gives `/etc/vector/conf.d` and `/var/lib/vector` to the user's current IDs, so that the user can write pipelines and Vector can keep its checkpoints.
