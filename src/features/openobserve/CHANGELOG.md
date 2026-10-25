# Changelog

## 1.1.0

### Features

- Installs the official OpenObserve OSS binary and runs it as an s6-overlay service for the selected user. It supports `amd64` and `arm64`.
- Option `dnsName` shows OpenObserve over HTTPS through the Caddy feature.
- Option `s3BucketPrefix` sets an object-key prefix. Several containers can share one S3 bucket when each uses a different prefix. The prefix, with its trailing slash, can be at most 256 characters.

### Fixes

- A root user password with shell quote characters is kept as you typed it.
