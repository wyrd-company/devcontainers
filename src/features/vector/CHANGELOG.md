# Changelog

## 1.0.0

Graduates from `0.x` to `1.0.0`.

### Breaking

- Adds the Vector Feature. Vector runs as an s6-overlay service and loads, reloads and unloads pipeline files in `/etc/vector/conf.d` without a restart. Pipelines read secrets as `SECRET[environment.NAME]`, including values from the OpenBao Agent secret file.
