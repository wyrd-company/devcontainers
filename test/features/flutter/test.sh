#!/usr/bin/env bash
set -e
source dev-container-features-test-lib
check "Dart runs" dart --version
check "Standalone Dart owns global command" test "$(readlink -f /usr/local/bin/dart)" = /opt/dart-sdk/bin/dart
check "Flutter runs" flutter --version
sample_dir="$(mktemp -d)"
cd "$sample_dir"
flutter create --platforms=linux,web sample_app
cd sample_app
check "Flutter widget test" flutter test
check "Flutter Linux build" flutter build linux
check "Flutter web build" flutter build web
rm -rf "$sample_dir"

reportResults
