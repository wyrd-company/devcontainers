---
title: Secrets
product: base
order: 5
---

`bao-secret` reads one field of an [OpenBao](https://openbao.org/) KV version 2 secret and prints it. It uses the image's `curl` and `jq`, so nothing has to be installed, and it never writes a secret to disk or puts one in an environment variable or on a command line.

```bash
bao-secret get secret/sample-application/token
```

A reference is `<mount>/<path>/<field>`: the first segment is the KV mount, the last is the field, and the segments between are the secret's path. Segments hold only letters, digits, `.`, `_` and `-`. String, number and boolean fields are printed; other fields are an error.

## Address

`bao-secret` reads the OpenBao address from `BAO_ADDR`, then `VAULT_ADDR`: `unix:///path/to.sock` or `http(s)://host:port`. It sends no token, so the address must authenticate the caller itself. When the container is bound to [Wyrwood](https://wyrd.foo/tools/wyrwood/), the environment holds `BAO_ADDR=unix:///run/wyrwood/vault.sock` and the socket does this. An [OpenBao Agent](https://openbao.org/docs/agent-and-proxy/agent/) API proxy with auto-auth works the same way.

## Errors

`bao-secret` exits with status 1 and a message on standard error when the address is missing or unreachable, the secret is not found or not permitted, or the field is missing. It exits with status 2 for a malformed reference. Messages name the secret and field, never a value.

## Vector

`bao-secret vector` answers [Vector](https://vector.dev/)'s `exec` secret backend protocol: it reads a request on standard input and writes each value, or an error, on standard output. The Vector Feature configures it as the `openbao` backend, so a pipeline reads a field as `SECRET[openbao.secret/sample-application/token]`. Each secret is read once per request, however many of its fields are requested.

`bao-secret` keeps values out of files and the environment, but it cannot control what the program that receives a value does with it. Vector, for example, can print a resolved value in a configuration error; the Vector Feature's documentation says where to place secrets.
