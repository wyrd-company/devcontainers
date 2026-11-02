#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
expect_rejection() {
    local feature="$1" value="$2" expected="$3" output
    if output="$(env "$value" bash "$root/src/features/$feature/install.sh" 2>&1)"; then
        echo "Expected rejection: $feature $value" >&2
        exit 1
    fi
    [[ "$output" == *"$expected"* ]] || { echo "$output" >&2; exit 1; }
}
expect_rejection dart VERSION=invalid 'full SDK version'
expect_rejection dart VERSION='1.2.3;false' 'full SDK version'
expect_rejection flutter CHANNEL='stable;false' 'Invalid Flutter channel'
expect_rejection flutter ANDROIDSDK=invalid 'androidSdk must be'
expect_rejection flutter ANDROIDAPILEVEL='35;false' 'Invalid Android API'
expect_rejection flutter ANDROIDBUILDTOOLS='35.0.0;false' 'Invalid Android build-tools'
expect_rejection flutter VERSION=invalid 'full SDK version'
echo 'Invalid SDK options rejected before installation.'
