# Dart SDK

Installs the standalone [Dart](https://dart.dev/) SDK from the stable archive into `/opt/dart-sdk`,
with its published SHA256 checksum checked before extraction. Supports Debian and Ubuntu on amd64
and arm64. Flutter is not installed.

The remote user owns the SDK. The `dart` command is linked through their `~/.local/bin` into
`/usr/local/bin`. Pub uses its native `~/.pub-cache`; add that directory to your mounts if it should
survive rebuilds. No mounts are declared.

## Usage

```json
{
  "features": {
    "ghcr.io/wyrd-company/devcontainers/dart:1": {}
  }
}
```

## Options

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| version | string | latest | Latest stable Dart or a full version, with optional `v` prefix. |

## Trademarks

Dart is a trademark of Google LLC. This Feature is not affiliated with or endorsed by Google. The
logo uses the [official Dart
mark](https://raw.githubusercontent.com/dart-lang/site-www/main/site/web/assets/img/logo/dart-192.svg),
in the shared Feature frame.
