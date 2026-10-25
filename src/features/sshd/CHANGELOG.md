# Changelog

## 1.1.0

### Features

- The SSH host keys are stored in a named volume. The server fingerprint stays the same when you rebuild the container. To rotate the keys, remove the volume.

## 1.0.0

### Features

- Adds an SSH server that runs as an s6-overlay service.
- Option `gatewayPorts` lets other hosts on the network connect to forwarded ports.

### Fixes

- Only public key logins are allowed. Password logins and root logins are off.
