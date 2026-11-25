#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Tags the images each architecture pushed by digest once as <repository>:<commit-sha>, only from
# the default branch, and writes the result as `image`, <repository>:<commit-sha>@<digest>, to
# GITHUB_OUTPUT. One architecture's image keeps its own manifest, whose labels a registry shows;
# several share one index, from which Docker pulls each host's own and which carries the same
# metadata as annotations, since GHCR reads a multi-architecture image's from its index. An
# annotation would wrap a single image in an index, so one architecture's image gets none. A
# commit's tag is written once, so a re-run never replaces the image an environment ran.
#
# Environment:
# - DIGESTS_DIRECTORY: an empty file per architecture's image, named for its digest's hex.
# - IMAGE_REPOSITORY: where it's published.
# - ANNOTATIONS: the index's annotations, one `index:<key>=<value>` per line.
# - DEFAULT_BRANCH: the repository's default branch.
# - GITHUB_REF, GITHUB_SHA, GITHUB_OUTPUT: set by GitHub Actions.

set -euo pipefail

if [ "$GITHUB_REF" != "refs/heads/$DEFAULT_BRANCH" ]; then
  echo "::error::Images are published only from $DEFAULT_BRANCH, not $GITHUB_REF"
  exit 1
fi
commit_tag="$IMAGE_REPOSITORY:$GITHUB_SHA"
if docker buildx imagetools inspect "$commit_tag" > /dev/null 2>&1; then
  echo "$commit_tag is already published"
else
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
    done <<<"$ANNOTATIONS"
  fi
  docker buildx imagetools create --prefer-index=false "${annotation_flags[@]}" --tag "$commit_tag" "${sources[@]}"
fi

docker buildx imagetools inspect "$commit_tag"
digest=$(docker buildx imagetools inspect "$commit_tag" --format '{{json .Manifest}}' | jq -r .digest)
case "$digest" in
  sha256:*) ;;
  *) echo "::error::$commit_tag has no digest ('$digest')"; exit 1 ;;
esac
echo "image=$commit_tag@$digest" >> "$GITHUB_OUTPUT"
echo "Published $commit_tag@$digest"
