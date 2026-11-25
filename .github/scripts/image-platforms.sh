#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Writes the platforms of a published image, each with its own digest, as the step's `platforms`
# output, a JSON list of {platform, digest}: one entry for an image of one architecture, one per
# architecture for an index.
#
# Environment:
# - IMAGE_REPOSITORY: where the image is published.
# - DIGEST: the published image's digest.
# - GITHUB_OUTPUT: set by GitHub Actions.

set -euo pipefail

case "$DIGEST" in
  sha256:*) ;;
  *) echo "::error::The image must name its digest, as <repository>[:<tag>]@sha256:<hex>"; exit 1 ;;
esac
image="$IMAGE_REPOSITORY@$DIGEST"
manifest=$(docker buildx imagetools inspect "$image" --raw)
case "$(jq -r '.mediaType // empty' <<<"$manifest")" in
  application/vnd.oci.image.index.v1+json|application/vnd.docker.distribution.manifest.list.v2+json)
    platforms=$(jq -c '[.manifests[]
      | select(.platform.os != "unknown")
      | {platform: ([.platform.os, .platform.architecture, .platform.variant // empty] | join("/")),
         digest}]' <<<"$manifest")
    ;;
  *)
    config=$(docker buildx imagetools inspect "$image" --format '{{json .Image}}')
    platforms=$(jq -c --arg digest "$DIGEST" \
      '[{platform: ([.os, .architecture, .variant // empty] | join("/")), digest: $digest}]' <<<"$config")
    ;;
esac
if [ "$(jq length <<<"$platforms")" -eq 0 ]; then
  echo "::error::$image names no platform"
  exit 1
fi
echo "platforms=$platforms" >> "$GITHUB_OUTPUT"
jq -r '.[] | "\(.platform): \(.digest)"' <<<"$platforms"
