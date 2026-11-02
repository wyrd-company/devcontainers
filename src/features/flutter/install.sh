#!/usr/bin/env bash
# Adapted from wyrd-company/the-wyrding-way-design-system src/flutter/install.sh.
# relationships: {references: devcontainer-feature.json}
set -euo pipefail
FEATURE=flutter
source "$(dirname "$0")/common.sh"
preflight
version="${VERSION:-latest}"
version="${version#v}"
channel="${CHANNEL:-stable}"
android="${ANDROIDSDK:-true}"
ANDROID_API_LEVEL="${ANDROIDAPILEVEL:-35}"
ANDROID_BUILD_TOOLS_VERSION="${ANDROIDBUILDTOOLS:-35.0.0}"
case "$channel" in stable|beta|master) ;; *) err "Invalid Flutter channel." ;; esac
case "$android" in true|false) ;; *) err "androidSdk must be true or false." ;; esac
[[ "$ANDROID_API_LEVEL" =~ ^[0-9]+$ ]] || err "Invalid Android API level."
[[ "$ANDROID_BUILD_TOOLS_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || err "Invalid Android build-tools version."
case "$version" in latest|stable) ref="$channel" ;; *) validate_version "$version"; ref="$version" ;; esac
[ -x /opt/dart-sdk/bin/dart ] || err "Install the Dart Feature first."
[ ! -e /opt/flutter ] || err "/opt/flutter already exists."
packages ca-certificates curl git unzip zip xz-utils jq python3 clang cmake ninja-build pkg-config libgtk-3-dev libgl1-mesa-dri mesa-utils
if [ "$android" = true ]; then packages openjdk-17-jdk-headless; fi
export FLUTTER_HOME=/opt/flutter ANDROID_HOME=/opt/android-sdk ANDROID_SDK_ROOT=/opt/android-sdk
export PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig:/usr/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}" GALLIUM_DRIVER="${GALLIUM_DRIVER:-llvmpipe}"
export PATH="/usr/local/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
install_android_cmdline_tools() {
    curl -fsSL https://developer.android.com/studio -o "$work/android.html"
    python3 - "$work/android.html" > "$work/android-download" <<'PYTHON'
import re, sys
page = open(sys.argv[1]).read()
rows = re.findall(r'<tr\b[^>]*>(.*?)</tr>', page, re.S)
for row in rows:
    name = re.search(r'commandlinetools-linux-[0-9]+_latest\.zip', row)
    checksum = re.search(r'\b[a-fA-F0-9]{64}\b', row)
    if name and checksum:
        print(name[0], checksum[0]); break
else:
    sys.exit('Could not find Android Linux command-line tools and SHA256.')
PYTHON
    read -r archive checksum < "$work/android-download"
    curl -fsSL "https://dl.google.com/android/repository/$archive" -o "$work/android.zip"
    printf '%s  %s\n' "$checksum" "$work/android.zip" | sha256sum -c -
    unzip -q "$work/android.zip" -d "$work/android"
    install -d "$ANDROID_HOME/cmdline-tools"
    mv "$work/android/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
}
install_android_packages() {
  install_android_cmdline_tools

  (yes || true) | sdkmanager --sdk_root="${ANDROID_HOME}" \
    "cmdline-tools;latest" \
    "platform-tools" \
    "platforms;android-${ANDROID_API_LEVEL}" \
    "build-tools;${ANDROID_BUILD_TOOLS_VERSION}"

  (yes || true) | sdkmanager --sdk_root="${ANDROID_HOME}" --licenses
}


# Git retains the SDK's release identity so flutter upgrade remains available.
git clone --depth 1 --branch "$ref" https://github.com/flutter/flutter.git /opt/flutter
chown -R "$sdk_user:$sdk_group" /opt/flutter
link_tool flutter /opt/flutter/bin/flutter
if [ "$android" = true ]; then
    install_android_packages
    chown -R "$sdk_user:$sdk_group" "$ANDROID_HOME"
    as_user flutter config --android-sdk "$ANDROID_HOME"
fi
as_user flutter config --no-analytics
as_user flutter precache
as_user flutter --version --machine > "$work/flutter-version.json"
case "$version" in latest|stable) ;; *)
    [ "$(jq -r .frameworkVersion "$work/flutter-version.json")" = "$version" ] || err "Installed Flutter version differs."
esac
log "Installed Flutter $(jq -r .frameworkVersion "$work/flutter-version.json")."
