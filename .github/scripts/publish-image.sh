#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Pushes the image once as <repository>:<commit-sha>, only from main.
#
# Environment:
# - CI_IMAGE: the image built for this commit.
# - IMAGE_REPOSITORY: where it's published.

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
docker tag "$CI_IMAGE" "$commit_tag"
docker push "$commit_tag"
