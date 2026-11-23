---
openbao-agent: patch
---

The README no longer lists the Vector Feature as a consumer of `/run/openbao/secrets/<feature-id>.env`: Vector 2 reads secrets with the base image's `bao-secret`. Remove any template that still writes `vector.env`.
