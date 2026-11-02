# Flutter SDK

The [Flutter](https://flutter.dev/) SDK installs into `/opt/flutter` and depends on
the [Dart](https://dart.dev/) Feature. Flutter keeps its matching Dart SDK internally;
the global `dart` command uses the standalone installation.

Optional [Android](https://developer.android.com/) tooling installs into `/opt/android-sdk`
and accepts SDK licenses. Linux desktop dependencies and Mesa software rendering
are included. Native Android tools may require amd64; set `androidSdk: false` for
Flutter web and Linux-only work on arm64.

SDKs are user-owned. No mounts are declared. Mount SDK and native user cache paths
explicitly if they must survive a rebuild. See [README.md](README.md) for options,
persistence paths, and source provenance.

## Trademarks

Flutter is a trademark of Google LLC. This Feature is not affiliated with or endorsed by Google. The logo uses the [official Flutter mark](https://raw.githubusercontent.com/flutter/website/main/sites/docs/web/assets/images/branding/flutter/logo/default.svg), in the shared Feature frame.
