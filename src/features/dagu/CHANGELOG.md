# Changelog

## 1.1.0

### Features

- Dagu loads `NAME=value` lines from `/run/openbao/secrets/dagu.env` when the file exists. Workflows read them as environment variables.
- When the OpenBao Agent feature renders this file, Dagu waits for it before it starts.

## 1.0.0

### Features

- Installs the official Dagu binary and runs `dagu start-all` as an s6-overlay service for the selected user.
- Options `host` and `port` set the address that Dagu uses.
- Option `dnsName` shows Dagu over HTTPS through the Caddy feature.
- Option `serviceUser` selects the user that runs Dagu.
