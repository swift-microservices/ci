#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Fails when the image runs as root or its product misses a runtime library.
#
# Environment:
# - CI_IMAGE: the image built for this commit.
# - EXECUTABLE_PRODUCT: the executable at /app/<product>.

set -euo pipefail

image_user=$(docker image inspect --format '{{.Config.User}}' "$CI_IMAGE")
case "$image_user" in
  ""|root|root:*|0|0:*) echo '::error::The image must run as an unprivileged user'; exit 1 ;;
esac

if linkage=$(docker run --rm --entrypoint ldd "$CI_IMAGE" "/app/$EXECUTABLE_PRODUCT" 2>&1); then
  printf '%s\n' "$linkage"
  if [[ $linkage == *'not found'* ]]; then
    echo '::error::A runtime library is missing from the image'
    exit 1
  fi
elif [[ $linkage == *'not a dynamic executable'* || $linkage == *'statically linked'* ]]; then
  printf '%s\n' "$linkage"
else
  printf '%s\n' "$linkage" >&2
  exit 1
fi
