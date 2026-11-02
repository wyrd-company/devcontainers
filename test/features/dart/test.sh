#!/usr/bin/env bash
set -e
source dev-container-features-test-lib
check "Dart runs" dart --version
check "Standalone Dart owns global command" test "$(readlink -f /usr/local/bin/dart)" = /opt/dart-sdk/bin/dart
check "Flutter is absent" test ! -e /opt/flutter
sample_dir="$(mktemp -d)"
cd "$sample_dir"
printf 'void main() { print("sample-dart"); }\n' > sample.dart
check "Dart executes a program" dart run sample.dart
rm -rf "$sample_dir"

reportResults
