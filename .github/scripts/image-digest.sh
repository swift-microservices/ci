#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Writes the digest of this commit's published image as the step's `digest` output.
#
# Environment:
# - IMAGE_REPOSITORY: where the image is published.
# - GITHUB_SHA, GITHUB_OUTPUT: set by GitHub Actions.

set -euo pipefail

image="$IMAGE_REPOSITORY:$GITHUB_SHA"
if ! digest=$(docker buildx imagetools inspect "$image" --format '{{.Manifest.Digest}}' 2>/dev/null) || [ -z "$digest" ]; then
  echo "::error::$image isn't published; attest it after service.yml publishes it"
  exit 1
fi
echo "digest=$digest" >> "$GITHUB_OUTPUT"
echo "$image is $digest"
