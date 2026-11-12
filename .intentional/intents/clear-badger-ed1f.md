---
vector:
  bump: major
  graduate: true
---

Adds the Vector Feature. Vector runs as an s6-overlay service and loads, reloads and unloads pipeline files in `/etc/vector/conf.d` without a restart. Pipelines read secrets as `SECRET[environment.NAME]`, including values from the OpenBao Agent secret file.
