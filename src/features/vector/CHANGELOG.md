# Changelog

## 2.0.0

### Breaking

- Secrets come from OpenBao through the base image's `bao-secret`: reference a field as `SECRET[openbao.<mount>/<path>/<field>]`. **Breaking:** the `environment` secret backend and the loading of `/run/openbao/secrets/vector.env` into Vector's environment are removed, along with the `openbao-secrets` group membership and s6 dependency, so secrets are no longer written to disk or put in environment variables. Replace `SECRET[environment.NAME]` with the OpenBao reference of the same value, and remove the OpenBao Agent `template` that writes `/run/openbao/secrets/vector.env`, which would otherwise keep writing the secrets to disk.

## 1.0.1

### Fixes

- The service runs when the Dev Container CLI changes the user's UID and GID to match the host user. At start, it gives `/etc/vector/conf.d` and `/var/lib/vector` to the user's current IDs, so that the user can write pipelines and Vector can keep its checkpoints.

## 1.0.0

Graduates from `0.x` to `1.0.0`.

### Breaking

- Adds the Vector Feature. Vector runs as an s6-overlay service and loads, reloads and unloads pipeline files in `/etc/vector/conf.d` without a restart. Pipelines read secrets as `SECRET[environment.NAME]`, including values from the OpenBao Agent secret file.
