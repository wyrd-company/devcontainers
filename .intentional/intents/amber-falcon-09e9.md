---
vector: major
---

Secrets come from OpenBao through the base image's `bao-secret`: reference a field as `SECRET[openbao.<mount>/<path>/<field>]`. **Breaking:** the `environment` secret backend and the loading of `/run/openbao/secrets/vector.env` into Vector's environment are removed, along with the `openbao-secrets` group membership and s6 dependency, so secrets are no longer written to disk or put in environment variables. Replace `SECRET[environment.NAME]` with the OpenBao reference of the same value.
