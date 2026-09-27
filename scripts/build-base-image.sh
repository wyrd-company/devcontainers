#!/usr/bin/env bash
#
# Builds the Ubuntu base image from this checkout and prints its tag.
#
# Runtime tests build on this image rather than the published one, so that they
# test a Feature against the base it will ship with. Images publish only after CI
# passes, so the published base can lag the checkout.

set -euo pipefail

variant="${1:-noble}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tag="devcontainers-base:${variant}"

docker build \
    --build-arg "VARIANT=${variant}" \
    --tag "${tag}" \
    "${repo_root}/src/images/base-ubuntu" >&2

echo "${tag}"
