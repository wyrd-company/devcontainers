# Dart SDK

The standalone [Dart](https://dart.dev/) SDK installs into `/opt/dart-sdk`. The remote
user owns it, and `dart` is available globally. Pub stores packages in `~/.pub-cache`.
Mount that path explicitly to keep it across rebuilds; no mounts are declared.

## Trademarks

Dart is a trademark of Google LLC. This Feature is not affiliated with or endorsed by Google. The logo uses the [official Dart mark](https://raw.githubusercontent.com/dart-lang/site-www/main/site/web/assets/img/logo/dart-192.svg), in the shared Feature frame.
