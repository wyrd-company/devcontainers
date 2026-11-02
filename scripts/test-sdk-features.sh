#!/usr/bin/env bash
# relationships: {references: ../test/features/flutter/runtime.Dockerfile}
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
base_image="${1:-debian:bookworm}"
if [ "$base_image" = local-base ]; then
    base_image="$("$repo_root/scripts/build-base-image.sh")"
fi
for target in dart flutter; do
    image="sample-sdk-${target}:test"
    docker build --build-arg BASE_IMAGE="$base_image" \
        --build-arg ANDROID_SDK="${ANDROID_SDK:-false}" \
        --target "$target" -t "$image" \
        -f "$repo_root/test/features/flutter/runtime.Dockerfile" "$repo_root"
    "$repo_root/scripts/check-sudo-no-all.sh" "$image"
done
