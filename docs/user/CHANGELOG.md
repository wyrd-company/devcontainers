# Changelog

## 0.1.4

### Fixes

- Combine the two highlights about image tags into one, so the base image page has the six highlights wyrd.foo allows and publishes again.

## 0.1.3

### Features

- Add `bao-secret`, which reads a field of an OpenBao KV version 2 secret through `BAO_ADDR` or `VAULT_ADDR` with the image's `curl` and `jq`, and answers Vector's `exec` secret backend protocol. It never writes a secret to disk, the environment or a command line.

## 0.1.2

### Fixes

- Document the container startup grace period and s6 readiness requirements.

## 0.1.1

### Features

- Services documents the D-Bus session bus: its socket, the `DBUS_SESSION_BUS_ADDRESS` it sets, who may connect, and why clients must keep the address in their environment.
