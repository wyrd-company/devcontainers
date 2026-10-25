# Changelog

## 1.0.0

### Features

- Installs Go and common Go tools, including `golangci-lint`.
- Based on the Microsoft Go feature. This feature does not request the Docker `--init` option, so the image keeps its own init system as PID 1.
- Options `version` and `golangciLintVersion` select the versions to install.
