# Changelog

## 1.2.0

### Features

- When the Ansible Feature is installed, the services of this Feature start after its `ansible-setup` oneshot succeeds. Without Ansible, startup does not change. The Feature adds the Ansible Feature to `installsAfter`.

## 1.1.0

### Features

- The Collector loads `NAME=value` lines from `/run/openbao/secrets/opentelemetry-collector.env` when the file exists. Use `${env:NAME}` in the configuration, so the file holds no credential.
- When the OpenBao Agent feature renders this file, the Collector waits for it before it starts.

## 1.0.0

### Features

- Installs the OpenTelemetry Collector core or contrib distribution and runs it as an s6-overlay service for the selected user. It supports `amd64` and `arm64`.
- Option `distribution` selects `core` or `contrib`. Option `version` selects the version.
- The command `opentelemetry-collector` points to the installed binary.

### Fixes

- The release lookup during install requests less data.
