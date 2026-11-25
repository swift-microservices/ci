#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Tags the images each architecture pushed by digest once as <repository>:<commit-sha>, only from
# main. One architecture's image keeps its own manifest; several share one index, from which Docker
# pulls each host's own.
#
# Environment:
# - DIGESTS_DIRECTORY: an empty file per architecture's image, named for its digest's hex.
# - IMAGE_REPOSITORY: where it's published.
# - GITHUB_REF, GITHUB_SHA: set by GitHub Actions.

set -euo pipefail

if [ "$GITHUB_REF" != refs/heads/main ]; then
  echo "::error::Images are published only from main, not $GITHUB_REF"
  exit 1
fi
commit_tag="$IMAGE_REPOSITORY:$GITHUB_SHA"
# A commit's tag is written once, so a re-run never replaces the image staging ran.
if docker buildx imagetools inspect "$commit_tag" > /dev/null 2>&1; then
  echo "$commit_tag is already published"
  exit 0
fi
sources=()
for file in "$DIGESTS_DIRECTORY"/*; do
  [ -f "$file" ] || continue
  sources+=("$IMAGE_REPOSITORY@sha256:$(basename "$file")")
done
if [ "${#sources[@]}" -eq 0 ]; then
  echo "::error::No architecture pushed an image to publish"
  exit 1
fi
docker buildx imagetools create --prefer-index=false --tag "$commit_tag" "${sources[@]}"
docker buildx imagetools inspect "$commit_tag"
