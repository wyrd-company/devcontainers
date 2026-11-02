# Flutter SDK

Installs [Flutter](https://flutter.dev/) from its official Git repository into `/opt/flutter`, Linux
desktop build and debugging packages, and optional [Android](https://developer.android.com/) tooling
into `/opt/android-sdk`. Supports Debian and Ubuntu on amd64 and arm64. The remote user owns both
SDK directories and can run `flutter upgrade` without sudo.

This Feature requires `ghcr.io/wyrd-company/devcontainers/dart:1` through `dependsOn`; the Dev
Container CLI installs it automatically. The global `dart` command remains the standalone SDK from
the [Dart](https://dart.dev/) Feature. Flutter manages its own matching Dart SDK and engine
artifacts in `/opt/flutter/bin/cache` using its native bootstrap and precache commands. Do not
replace that SDK with the standalone SDK. To pin standalone Dart, declare the Dart Feature
explicitly with its `version` option.

Linux desktop tools include [Clang](https://clang.llvm.org/), [CMake](https://cmake.org/),
[Ninja](https://ninja-build.org/), [pkg-config](https://www.freedesktop.org/wiki/Software/pkg-config/),
[GTK](https://www.gtk.org/) development headers, and [Mesa](https://www.mesa3d.org/)
DRI and utilities. Both architecture-specific system pkg-config directories are exported. Mesa
software rendering defaults to `LIBGL_ALWAYS_SOFTWARE=1` and `GALLIUM_DRIVER=llvmpipe`.

Android installs [OpenJDK](https://openjdk.org/) 17, command-line tools (verified against the SHA256 published on the Android
Studio download page), platform-tools, the selected platform, and build-tools. SDK package downloads
use sdkmanager. Installation accepts Android SDK licenses. Google's Linux
native Android tools may require amd64; use `androidSdk: false` for Dart, Flutter web, and
Linux-only work on arm64. Android emulators and an attached display are not provided.

Configuration and cache stay in native locations: `~/.config/flutter`, `~/.pub-cache`, `~/.android`,
and the SDK directories. Mount those paths explicitly if you want persistence; no mounts are
declared. `FLUTTER_HOME`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`, the Android command paths, pkg-config
paths, and rendering defaults are supplied through Feature metadata.

## Usage

```json
{
  "features": {
    "ghcr.io/wyrd-company/devcontainers/flutter:1": {}
  }
}
```

## Options

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| version | string | latest | Latest selected channel (`stable` is an alias), or full Flutter tag with optional `v` prefix. |
| channel | string | stable | Channel for latest: stable, beta, or master. |
| androidSdk | boolean | true | Install Android tooling and accept its licenses. |
| androidApiLevel | string | 35 | Android platform API level. |
| androidBuildTools | string | 35.0.0 | Android build-tools version. |

## Trademarks

Flutter is a trademark of Google LLC. This Feature is not affiliated with or endorsed by Google. The
logo uses the [official Flutter
mark](https://raw.githubusercontent.com/flutter/website/main/sites/docs/web/assets/images/branding/flutter/logo/default.svg),
in the shared Feature frame.
