#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Tags the images each architecture pushed by digest once as <repository>:<commit-sha>, only from
# main. One architecture's image keeps its own manifest, whose labels GHCR shows; several share one
# index, from which Docker pulls each host's own and which carries the same metadata as annotations,
# since GHCR reads a multi-architecture image's from its index. An annotation would wrap a single
# image in an index, so one architecture's image gets none.
#
# Environment:
# - DIGESTS_DIRECTORY: an empty file per architecture's image, named for its digest's hex.
# - IMAGE_REPOSITORY: where it's published.
# - ANNOTATIONS: the index's annotations, one `index:<key>=<value>` per line.
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
annotation_flags=()
if [ "${#sources[@]}" -gt 1 ]; then
  while IFS= read -r annotation; do
    if [ -n "$annotation" ]; then
      annotation_flags+=(--annotation "$annotation")
    fi
  done <<< "$ANNOTATIONS"
fi
docker buildx imagetools create --prefer-index=false "${annotation_flags[@]}" --tag "$commit_tag" "${sources[@]}"
docker buildx imagetools inspect "$commit_tag"
