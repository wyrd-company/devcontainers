#!/usr/bin/env bash
# relationships: {references: devcontainer-feature.json}
set -euo pipefail
FEATURE=dart
source "$(dirname "$0")/common.sh"
preflight
version="${VERSION:-latest}"
version="${version#v}"
[ "$version" = latest ] || validate_version "$version"
packages ca-certificates curl unzip jq
if [ "$version" = latest ]; then
    version="$(curl -fsSL https://storage.googleapis.com/dart-archive/channels/stable/release/latest/VERSION | jq -er .version)"
fi
validate_version "$version"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
archive="dartsdk-linux-${sdk_arch}-release.zip"
url="https://storage.googleapis.com/dart-archive/channels/stable/release/${version}/sdk/${archive}"
curl -fsSL "$url" -o "$work/$archive"
curl -fsSL "$url.sha256sum" -o "$work/checksum"
checksum="$(awk '{print $1}' "$work/checksum")"
[[ "$checksum" =~ ^[a-fA-F0-9]{64}$ ]] || err "Invalid Dart SHA256 checksum."
printf '%s  %s\n' "$checksum" "$work/$archive" | sha256sum -c -
unzip -q "$work/$archive" -d "$work"
[ ! -e /opt/dart-sdk ] || err "/opt/dart-sdk already exists."
mv "$work/dart-sdk" /opt/dart-sdk
chown -R "$sdk_user:$sdk_group" /opt/dart-sdk
link_tool dart /opt/dart-sdk/bin/dart
as_user /opt/dart-sdk/bin/dart --version 2>&1 | tee "$work/version"
grep -F "Dart SDK version: ${version} " "$work/version" >/dev/null || err "Installed Dart version differs."
log "Installed Dart ${version}."
